#!/usr/bin/env python3
"""Disposable real-host observations. No UI activation or real RSS sites."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from x23_vm import LabVM

workspace = Path(__file__).resolve().parents[2]
evidence = workspace / 'docs/next/evidence/x31'
observation_only = '--observation-only' in sys.argv
controls_only = '--controls-only' in sys.argv
empty_only = '--empty-session' in sys.argv
terminal_only = '--terminal-only' in sys.argv
if observation_only:
    evidence = evidence / 'prepared-source'
elif controls_only:
    evidence = evidence / 'controls'
elif empty_only:
    evidence = evidence / 'empty-session'
elif terminal_only:
    evidence = evidence / 'terminal'
evidence.mkdir(exist_ok=True, parents=True)
profile = 'x31-' + str(os.getpid())
root = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
assert not root.exists()
root.mkdir(parents=True, mode=0o700)
records, tokens, requests, pids = [], [], [], []
released = False
app = endpoint = vm = None
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def record(label, value):
    records.append({'at': time.time(), 'label': label, 'value': value})
    print(label, json.dumps(value, ensure_ascii=False), flush=True)
    (evidence / 'experiment.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))


class RSS(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        requests.append({'at': time.time(), 'path': self.path, 'released': released})
        if self.path == '/rss':
            item = ('<item><title>星港来信 第01集</title><guid>star-letter-01</guid>'
                    '<enclosure url="http://127.0.0.1:%d/episode.txt" type="text/plain" length="28"/>'
                    '</item>' % self.server.server_port) if released else ''
            data = ('<?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel>'
                    '<title>星港来信实验发布源</title>' + item + '</channel></rss>').encode()
        elif self.path == '/episode.txt':
            data = b'X31 synthetic episode fixture\n'
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Content-Type', 'application/rss+xml' if self.path == '/rss' else 'text/plain')
        self.end_headers()
        self.wfile.write(data)


server = ThreadingHTTPServer(('127.0.0.1', 0), RSS)
threading.Thread(target=server.serve_forever, daemon=True).start()
feed = 'http://127.0.0.1:%d/rss' % server.server_port


def until(predicate, seconds=360):
    deadline = time.monotonic() + seconds
    while True:
        value = predicate()
        if value:
            return value
        assert app.poll() is None and time.monotonic() < deadline, 'observation timeout'
        time.sleep(.5)


def call(action, inputs, chat=False):
    headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + endpoint['token']}
    if chat:
        headers['X-NipaPlay-Chat'] = vm.chat('status')['header']['sessionId']
    request = urllib.request.Request(endpoint['url'], data=json.dumps({
        'operation': 'call', 'action': action, 'input': inputs}).encode(), headers=headers)
    with opener.open(request, timeout=60) as response:
        result = json.load(response)
    assert result['status'] == 'completed', (action, result)
    return result['result']


def launch(index):
    global app, endpoint, vm
    old = endpoint['token'] if endpoint else None
    log = root / ('app-%d.log' % index)
    with log.open('w') as stream:
        app = subprocess.Popen([str(workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
                               env=env, stdout=stream, stderr=subprocess.STDOUT)
    pids.append(app.pid)
    def ready():
        global endpoint, vm
        path = root / 'endpoint.json'
        if not path.exists():
            return False
        fresh = json.loads(path.read_text())
        if fresh['token'] == old:
            return False
        endpoint = fresh
        try:
            vm = LabVM(log)
            header = vm.chat('status')['header']
            return header.get('threadId') and header.get('model') and header['threadId'] == header.get('mainThreadId')
        except RuntimeError:
            return False
    until(ready, 120)
    tokens.append(endpoint['token'])
    assert vm.rpc('getVM')['pid'] == app.pid
    record('launch', {'pid': app.pid, 'header': vm.chat('status')['header']})


def stop():
    if app is not None and app.poll() is None:
        try:
            vm.chat('close')
        except RuntimeError as error:
            record('host-close-unavailable', str(error))
        finally:
            app.terminate()
            app.wait(timeout=20)
            record('stop', {'pid': app.pid, 'returncode': app.returncode})


def idle():
    status = vm.chat('status')['liveness']['status']
    return status not in ('starting', 'inProgress')


def row(identifier):
    return next(r for r in call('followup.list', {})['followups'] if r['id'] == identifier)


def finished(identifier):
    r = row(identifier)
    return r if r['state'] in ('completed', 'execution_failed') else False


config = (Path.home() / '.codex/config.toml').read_text()
config = re.sub(r'(?m)^model\s*=.*$', 'model = "deepseek-v4.1-flash"', config, count=1)
hosts = ['127.0.0.1', 'localhost']
hosts += [urllib.parse.urlparse(url).hostname for url in re.findall(r'(?m)^base_url\s*=\s*"([^"]+)"', config)]
home = root / 'codex-home'
home.mkdir(mode=0o700)
(home / 'config.toml').write_text(config)
(home / 'config.toml').chmod(0o600)
shutil.copy2(Path.home() / '.codex/auth.json', home / 'auth.json')
(home / 'skills').symlink_to(Path.home() / '.codex/skills', target_is_directory=True)
shutil.copy2('/etc/ssl/cert.pem', root / 'system-ca.pem')
env = os.environ.copy()
env.pop('NIPAPLAY_LAB_QUIET', None)
env.update(NIPAPLAY_PROFILE=profile, CODEX_CA_CERTIFICATE=str(root / 'system-ca.pem'),
           SSL_CERT_FILE=str(root / 'system-ca.pem'), NO_PROXY=','.join(hosts), no_proxy=','.join(hosts))
(root / 'preferences.json').write_text(json.dumps({
    'flutter.labs_enable_agent_endpoint': True, 'flutter.downloader_enabled': False,
    'flutter.nipaplay_scanned_folders': [str(root / 'data/empty')]}))
(root / 'data/empty').mkdir(parents=True)

try:
    if observation_only:
        harness = root / 'harness'
        shutil.copytree(workspace / 'assets/next/harness', harness)
        (harness / 'nipa').chmod(0o755)
        subprocess.run(['git', 'init', '--quiet', '--template=', '--initial-branch=main'], cwd=harness, check=True)
        with (harness / 'AGENTS.md').open('a') as stream:
            stream.write('\n## 本次实验环境事实\n星港来信是本次实验的虚构作品，唯一发布来源为 ' + feed +
                         ' 。当前还没有已发布的集数。该源只提供本机测试文本附件，不是真实视频或种子。'
                         '实验没有真实站点或实际登录；本次工作空间是临时 harness。\n')
    launch(0)
    harness = root / 'harness'
    main = vm.chat('status')['header']['mainThreadId']
    if empty_only:
        stop()
        launch(1)
        record('empty-main-restart', {'before': main, 'after': vm.chat('main')['thread']['id']})
        assert vm.chat('status')['header']['threadId'] == main
        raise SystemExit(0)
    if terminal_only:
        job = call('media.library.scan', {'root': str(root / 'data/empty'), 'requestId': 'x31-terminal'})['job']
        until(lambda: call('task.get', {'jobId': job['jobId']})['job']['state'] == 'succeeded')
        registration = call('followup.register', {'when': {'jobId': job['jobId']},
            'title': '终端默认主会话', 'instruction': '只回复：终端后续已回到主会话。'})['followup']
        result = until(lambda: finished(registration['id']))
        record('terminal-main-followup', result)
        assert result['state'] == 'completed' and result['threadId'] == main
        turn = result['turnId']
        call('activity.report', {'title': '版本已出现', 'source': 'x31-terminal-fixture',
                                'facts': {'version': '3', 'cookie': 'synthetic-private-cookie'}})
        stop()
        launch(1)
        record('restart-main', {'before': main, 'after': vm.chat('status')['header']['threadId']})
        assert vm.chat('status')['header']['threadId'] == main
        result = row(registration['id'])
        record('no-replay-after-restart', result)
        assert result['turnId'] == turn and result['state'] == 'completed'
        activity = call('state.query', {'view': 'activity', 'limit': 1000})
        (evidence / 'activity.json').write_text(json.dumps(activity, ensure_ascii=False, indent=2))
        raise SystemExit(0)
    agents = harness / 'AGENTS.md'
    if not observation_only:
        with agents.open('a') as stream:
            stream.write('\n## 本次实验环境事实\n星港来信是本次实验的虚构作品，唯一发布来源为 ' + feed +
                         ' 。当前还没有已发布的集数。该源只提供本机测试文本附件，不是真实视频或种子。'
                         '实验没有真实站点或实际登录；本次工作空间是临时 harness。\n')
    if not controls_only:
        initial_agents = agents.read_text()
        record('unhinted-input', '《星港来信》以后有更新就帮我准备好')
        record('unhinted-turn', vm.chat('turn', text='《星港来信》以后有更新就帮我准备好'))
        until(idle)
        record('unhinted-finished', vm.chat('status')['liveness'])
        snapshot = {}
        for path in harness.rglob('*'):
            if path.is_file() and '.git' not in path.parts and path.name != 'nipa':
                try:
                    value = path.read_text()
                except UnicodeError:
                    continue
                if path.name != 'AGENTS.md' or value != initial_agents:
                    snapshot[str(path.relative_to(harness))] = value
        (evidence / 'agent-harness.json').write_text(json.dumps(snapshot, ensure_ascii=False, indent=2))
        record('agent-files', list(snapshot))
        released = True
        record('fixture-release', {'guid': 'star-letter-01', 'observationSeconds': 20})
        end = time.monotonic() + 20
        while time.monotonic() < end:
            time.sleep(.5)
        record('rss-observations', requests)
        record('agent-jobs', call('task.list', {'type': 'harness.hook'}))
    if observation_only:
        (evidence / 'activity.json').write_text(json.dumps(
            call('state.query', {'view': 'activity', 'limit': 1000}), ensure_ascii=False, indent=2))
        raise SystemExit(0)
    if (harness / 'hooks/schedules.json').exists():
        (harness / 'hooks/schedules.json').rename(harness / 'hooks/observation-schedules.json')
    until(idle)

    # Separate infrastructure control: registration carries the actual new-chat origin.
    new = vm.chat('start')['thread']['id']
    empty = root / 'data/empty'
    empty.mkdir(parents=True, exist_ok=True)
    job = call('media.library.scan', {'root': str(empty), 'requestId': 'x31-empty'})['job']
    until(lambda: call('task.get', {'jobId': job['jobId']})['job']['state'] == 'succeeded')
    prompt = '请通过 ./nipa call followup.register 登记这个任务结束后的后续：' + json.dumps({
        'when': {'jobId': job['jobId']}, 'title': '新对话后续',
        'instruction': '告诉用户空目录扫描已结束，只需一句话，不用进一步操作。'}, ensure_ascii=False) + '。然后回复已登记即可。'
    record('new-dialogue-input', prompt)
    vm.chat('turn', text=prompt)
    registration = until(lambda: next((r for r in call('followup.list', {})['followups']
                                      if r['title'] == '新对话后续'), None))
    result = until(lambda: finished(registration['id']))
    record('new-dialogue-followup', {'newThread': new, 'mainThread': main, 'followup': result})
    assert result['threadId'] == new and new != main and result['state'] == 'completed'

    # Timer-generated wake defaults to main even with another conversation selected.
    script = harness / 'hooks/x31-control'
    script.write_text('#!/usr/bin/env python3\nimport json, pathlib, subprocess\n'
                      'payload=json.load(__import__("sys").stdin)\n'
                      'sentinel=pathlib.Path(".x31-control-sent")\n'
                      'if not sentinel.exists():\n'
                      ' subprocess.run(["python3","nipa","call","activity.report",json.dumps({"title":"实验脚本发现了变化","source":"x31-control","facts":{"version":"2"}})],check=True)\n'
                      ' subprocess.run(["python3","nipa","call","agent.wake",json.dumps({"title":"定时脚本唤醒","instruction":"告诉用户脚本发现了版本2，只回复一句话。","facts":{"version":"2","schedule":payload}})],check=True)\n'
                      ' sentinel.write_text("sent")\n'
                      'print("timer finished; cookie=synthetic-private-value")\n')
    script.chmod(0o755)
    vm.chat('turn', text='请执行 python3 -c \'import time; time.sleep(12); print("busy finished")\'，然后只回复完成。')
    (harness / 'hooks/schedules.json').write_text(json.dumps([
        {'id': 'x31-control', 'program': 'hooks/x31-control', 'everySeconds': 3}]))
    wake = until(lambda: next((r for r in call('followup.list', {})['followups']
                              if r['title'] == '定时脚本唤醒'), None))
    record('timer-queued', {'followup': wake, 'liveness': vm.chat('status')['liveness']})
    (harness / 'hooks/schedules.json').unlink()
    result = until(lambda: finished(wake['id']))
    record('timer-main-followup', result)
    assert result['threadId'] == main and result['state'] == 'completed'
    record('timer-receipts', call('task.list', {'type': 'harness.hook'}))
    record('sessions', vm.chat('sessions'))
    stop()
    launch(1)
    record('restart-main', {'before': main, 'after': vm.chat('status')['header']['threadId']})
    assert vm.chat('status')['header']['threadId'] == main
    terminal = call('followup.register', {'when': {'jobId': job['jobId']},
        'title': '终端默认主会话', 'instruction': '只回复：终端后续已回到主会话。'})['followup']
    result = until(lambda: finished(terminal['id']))
    record('terminal-main-followup', result)
    assert result['threadId'] == main and result['state'] == 'completed'
    activity = call('state.query', {'view': 'activity', 'limit': 1000})
    (evidence / 'activity.json').write_text(json.dumps(activity, ensure_ascii=False, indent=2))
finally:
    try:
        stop()
    finally:
        server.shutdown()
        server.server_close()
        path = root / 'chat-events.jsonl'
        if path.exists():
            text = path.read_text()
            for token in tokens:
                assert token not in text
            (evidence / 'chat.jsonl').write_text(text)
        shutil.rmtree(root)
        record('cleanup', {'rootAbsent': not root.exists(), 'lastPidStopped': app is None or app.poll() is not None,
                           'pids': pids})
