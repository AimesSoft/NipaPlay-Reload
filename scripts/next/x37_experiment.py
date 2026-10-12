#!/usr/bin/env python3
"""Real DeepSeek, disposable worktree app, no UI activation or SMB writes."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import sys
import shlex
import threading
from http.server import ThreadingHTTPServer
import urllib.parse
import urllib.request

from x23_vm import LabVM

workspace = Path(__file__).resolve().parents[2]
recovery = '--recovery-only' in sys.argv
return_only = '--return-only' in sys.argv
delivery = '--delivery-only' in sys.argv or return_only
controls = '--controls' in sys.argv or recovery
evidence = workspace / ('docs/next/evidence/x37/recovery' if recovery else
    'docs/next/evidence/x37/controls' if controls else
    'docs/next/evidence/x37/real-return' if return_only else
    'docs/next/evidence/x37/real-delivery' if delivery else 'docs/next/evidence/x37/real')
evidence.mkdir(parents=True, exist_ok=True)
profile = 'x37-real-' + str(os.getpid())
root = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
assert not root.exists()
root.mkdir(mode=0o700)
home = root / 'codex-home'
home.mkdir(mode=0o700)
server = None
if controls:
    from x37_provider import Provider
    server = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    config = ('model="deepseek-v4.1-flash"\nmodel_provider="fixture"\n'
        '[model_providers.fixture]\nname="fixture"\nwire_api="responses"\n'
        'base_url="http://127.0.0.1:%d/v1"\n' % server.server_port)
else:
    config = (Path.home() / '.codex/config.toml').read_text()
    config = re.sub(r'(?m)^model\s*=.*$', 'model = "deepseek-v4.1-flash"', config, count=1)
(home / 'config.toml').write_text(config)
(home / 'config.toml').chmod(0o600)
if not controls:
    shutil.copy2(Path.home() / '.codex/auth.json', home / 'auth.json')
(home / 'skills').symlink_to(Path.home() / '.codex/skills', target_is_directory=True)
shutil.copy2('/etc/ssl/cert.pem', root / 'system-ca.pem')
hosts = ['127.0.0.1', 'localhost'] + [urllib.parse.urlparse(url).hostname
    for url in re.findall(r'(?m)^base_url\s*=\s*"([^"]+)"', config)]
env = dict(os.environ)
env.pop('NIPAPLAY_LAB_QUIET', None)
env.update(NIPAPLAY_PROFILE=profile, CODEX_HOME=str(home),
    CODEX_CA_CERTIFICATE=str(root / 'system-ca.pem'), SSL_CERT_FILE=str(root / 'system-ca.pem'),
    NO_PROXY=','.join(hosts), no_proxy=','.join(hosts))
media = '/Volumes/Media/躲在超市后门抽烟的两人'
(root / 'preferences.json').write_text(json.dumps({
    'flutter.labs_enable_agent_endpoint': True, 'flutter.downloader_enabled': False,
    'flutter.labs_use_next_interface': False, 'flutter.auto_sync_enabled': False,
    'flutter.nipaplay_scanned_folders': [media]}))
harness = root / 'harness'
shutil.copytree(workspace / 'assets/next/harness', harness)
(harness / 'nipa').chmod(0o755)
subprocess.run(['git', 'init', '--quiet', '--template=', '--initial-branch=main'], cwd=harness, check=True)
with (harness / 'AGENTS.md').open('a') as stream:
    stream.write('\n## 本次实验环境\n片库根目录是 `' + media + '`，用户授权只读；'
        '不能写、改名、删或复制整部，不寻找 SMB 账号、不重新挂载。'
        '这是独立临时实例，没有用户登录账号。所有工作文件只能写在这个 harness。'
        '不读取用户真实 NipaPlay 数据目录、~/.config/nipaplay 或钥匙串，不打开登录窗口或浏览器。\n')
if delivery:
    wire = workspace / 'docs/next/evidence/x37/real/chat.jsonl'
    imports = []
    for line in wire.read_text().splitlines():
        message = json.loads(line)['m']
        if message.get('method') != 'item/completed':
            continue
        item = message['params']['item']
        command = item.get('command', '')
        if item['type'] == 'commandExecution' and (
                'BV1HBpw6vEZH:p1' in command and 'danmaku.import' in command or
                'work/import_all.py' in command or 'work/verify.py' in command):
            imports.append({'command': command, 'exitCode': item.get('exitCode'),
                            'output': item.get('aggregatedOutput')})
    (harness / 'completed-imports.json').write_text(json.dumps({
        'source': 'prior disposable X37 real DeepSeek experiment, app PID 35307',
        'profileAlreadyRemoved': True, 'records': imports}, ensure_ascii=False, indent=2))
    if return_only:
        previous = json.loads((workspace / 'docs/next/evidence/x37/real-delivery/timeline.json').read_text())
        result = next(row['value'][0]['receipt']['details'] for row in previous
            if row['label'] == 'helper-before-question')
        (harness / 'completed-result.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
records = []
app = vm = endpoint = None

def record(label, value):
    records.append({'at': time.time(), 'label': label, 'value': value})
    (evidence / 'timeline.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, json.dumps(value, ensure_ascii=False), flush=True)

def until(predicate, seconds=120):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        assert app.poll() is None, 'app exited'
        time.sleep(.5)
    raise RuntimeError('observation deadline reached')

def call(action, inputs):
    with opener.open(urllib.request.Request(endpoint['url'],
        data=json.dumps({'operation': 'call', 'action': action, 'input': inputs}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + endpoint['token']}),
        timeout=60) as response:
        result = json.load(response)
    assert result['status'] == 'completed', (action, result)
    return result['result']

def helpers():
    return call('task.list', {'type': 'agent.helper'})['jobs']

def idle():
    return vm.chat('status')['liveness']['status'] not in ('inProgress', 'starting')

def queued_turn(text):
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        if idle():
            try:
                return vm.chat('turn', text=text)
            except RuntimeError as error:
                if 'Use steer for an active turn' not in str(error):
                    raise
                # Automatic followup won the interval after the idle snapshot.
                record('user-input-queued', 'Waiting for the active followup.')
        time.sleep(.5)
    raise RuntimeError('queued user input observation deadline reached')

try:
    log = root / 'app.log'
    with log.open('w') as output:
        app = subprocess.Popen([str(workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
            env=env, stdout=output, stderr=subprocess.STDOUT)
    def ready():
        global vm, endpoint
        if not (root / 'endpoint.json').exists():
            return False
        endpoint = json.loads((root / 'endpoint.json').read_text())
        try:
            vm = LabVM(log)
            header = vm.chat('status')['header']
            return header['threadId'] and header['model'] and header['mainThreadId']
        except RuntimeError:
            return False
    until(ready)
    assert vm.rpc('getVM')['pid'] == app.pid
    record('launch', {'pid': app.pid, 'header': vm.chat('status')['header']})
    if controls:
        main = vm.chat('status')['header']['mainThreadId']
        def helper_command(seconds):
            code = ('import os,json,subprocess,time; '
                'id=os.environ["NIPAPLAY_CHAT"].removeprefix("helper-"); '
                'print("helper-env="+os.environ["NIPAPLAY_CHAT"]); '
                'subprocess.run(["./nipa","call","agent.helper.report",json.dumps({"currentActivity":"正在整理弹幕"})],check=True); '
                'subprocess.run(["./nipa","call","ui.present",json.dumps({"cards":[{"kind":"task","taskId":id}]})],check=True); '
                f'time.sleep({seconds}); print("帮手命令结束")')
            return 'CONTROL:python3 -c ' + shlex.quote(code)
        if recovery:
            accepted = call('agent.helper', {'title': '整理弹幕', 'instruction': helper_command(20)})
            until(lambda: any(j.get('currentActivity') == '正在整理弹幕' for j in helpers()))
            record('reported-activity', helpers())
            vm.chat('close')
            old_pid = app.pid
            app.terminate()
            app.wait(timeout=20)
            record('restart-stop', {'pid': old_pid, 'returncode': app.returncode})
            with log.open('w') as output:
                app = subprocess.Popen([str(workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
                    env=env, stdout=output, stderr=subprocess.STDOUT)
            until(ready)
            until(lambda: all(j['state'] in ('succeeded', 'failed', 'cancelled') for j in helpers()))
            until(lambda: all(r['state'] in ('completed', 'execution_failed') for r in call('followup.list', {})['followups']))
            record('recovered-job', helpers())
            record('recovered-followups', call('followup.list', {}))
            job = helpers()[0]
            record('helper-history', vm.chat('read', threadId=job['threadId']))
            record('main-after-restart', vm.chat('status')['header'])
            raise SystemExit(0)
        ids = []
        for seconds in [5, 20, 2, 2]:
            accepted = call('agent.helper', {'title': '整理弹幕', 'instruction': helper_command(seconds)})
            ids.append(accepted['jobId'])
        record('accepted-helpers', ids)
        until(lambda: sum(bool(j.get('threadId')) for j in helpers()) >= 2)
        record('capacity', helpers())
        record('main-while-helpers', vm.chat('turn', text='CONTROL:python3 -c ' +
            shlex.quote('import time; time.sleep(25); print("主会话仍在运行")')))
        record('cancel-queued', call('task.cancel', {'jobId': ids[2]}))
        until(lambda: next(j for j in helpers() if j['jobId'] == ids[0])['state'] == 'succeeded')
        record('finished-while-main-busy', {'jobs': helpers(), 'status': vm.chat('status'),
            'followups': call('followup.list', {})})
        record('cancel-running', call('task.cancel', {'jobId': ids[1]}))
        until(lambda: all(j['state'] in ('succeeded', 'failed', 'cancelled') for j in helpers()))
        until(lambda: all(r['state'] in ('completed', 'execution_failed') for r in call('followup.list', {})['followups']))
        record('terminal', helpers())
        record('delivered', call('followup.list', {}))
        record('history', vm.chat('read', threadId=main))
        record('activity', call('state.query', {'view': 'activity', 'limit': 1000}))
        import sqlite3
        database = next(root.rglob('next.db'))
        with sqlite3.connect('file:' + str(database) + '?mode=ro', uri=True) as db:
            record('cards', db.execute('SELECT thread_id,turn_id,origin,cards FROM ui_presentations').fetchall())
        for job in helpers():
            checkpoint = {'threadId': job.get('threadId'), 'turnId': job.get('turnId')}
            if checkpoint['threadId'] and not checkpoint['turnId']:
                checkpoint['turnId'] = vm.chat('status')['threads'][checkpoint['threadId']]['turnId']
            if checkpoint.get('threadId') and checkpoint.get('turnId'):
                record('process', call('chat.turn.process', {'threadId': checkpoint['threadId'], 'turnId': checkpoint['turnId']}))
        raise SystemExit(0)
    initial = ('把 completed-result.json 里已经核对好的结果交给一个帮手，只让它整理成给观众看的两句话。'
        '不重新核对、不搜索、不登录、不导入、不改业务状态。你派出去后结束这一轮，等它的自动后续回来。'
        if return_only else
        '把 completed-imports.json 里的已完成导入记录交给一个帮手核对，'
        '让它计算九集弹幕总条数并回报每集条数。只核对这份记录，不搜索、不登录、'
        '不重新导入或改任何业务状态。你派出去后先结束这一轮，我继续问别的。'
        if delivery else '把《躲在超市后门抽烟的两人》的弹幕都补上')
    record('user', initial)
    record('initial-turn', vm.chat('turn', text=initial))
    deadline = time.monotonic() + 100
    while time.monotonic() < deadline and not helpers() and not idle():
        time.sleep(1)
    if not helpers():
        record('explicit-user-request', '把这件事交给帮手继续做。我想继续聊别的。')
        if idle():
            record('delegation-turn', vm.chat('turn', text='把这件事交给帮手继续做。我想继续聊别的。'))
        else:
            record('delegation-steer', vm.chat('steer', text='把这件事交给帮手继续做。我想继续聊别的。'))
    until(lambda: helpers(), 180)
    until(idle, 180)
    record('helper-before-question', helpers())
    record('parallel-status', vm.chat('status'))
    if not return_only:
        record('other-question', queued_turn('BT 下载里的做种是什么意思？用两句话告诉我。'))
        until(idle, 180)
        record('other-answer-history', vm.chat('read', threadId=vm.chat('status')['header']['mainThreadId']))
        record('helper-after-question', helpers())
    until(lambda: all(j['state'] in ('succeeded', 'failed', 'cancelled') for j in helpers()), 720)
    record('helper-terminal', helpers())
    until(lambda: all(r['state'] in ('completed', 'execution_failed')
        for r in call('followup.list', {})['followups']), 240)
    record('followups', call('followup.list', {}))
    record('main-history', vm.chat('read', threadId=vm.chat('status')['header']['mainThreadId']))
    record('activity', call('state.query', {'view': 'activity', 'limit': 1000}))
    for job in helpers():
        checkpoint = {'threadId': job.get('threadId'), 'turnId': job.get('turnId')}
        if checkpoint['threadId'] and not checkpoint['turnId']:
            checkpoint['turnId'] = vm.chat('status')['threads'][checkpoint['threadId']]['turnId']
        if checkpoint.get('threadId') and checkpoint.get('turnId'):
            record('helper-process', call('chat.turn.process', {
                'threadId': checkpoint['threadId'], 'turnId': checkpoint['turnId']}))
except Exception as error:
    record('observation-error', str(error))
    raise
finally:
    if app is not None and app.poll() is None:
        if vm is not None:
            try:
                vm.chat('close')
            except Exception:
                pass
        app.terminate()
        app.wait(timeout=20)
    if (root / 'chat-events.jsonl').exists():
        shutil.copy2(root / 'chat-events.jsonl', evidence / 'chat.jsonl')
    # All public evidence passes the host redactor. Retain no config, auth,
    # endpoint file, raw application log or private VM address.
    if endpoint is not None:
        for path in evidence.glob('*'):
            if path.is_file():
                assert endpoint['token'] not in path.read_text(errors='replace')
    shutil.rmtree(root)
    if server is not None:
        server.shutdown()
    (evidence / 'cleanup.json').write_text(json.dumps({'pid': None if app is None else app.pid,
        'returncode': None if app is None else app.returncode, 'profileRemoved': not root.exists()}))
