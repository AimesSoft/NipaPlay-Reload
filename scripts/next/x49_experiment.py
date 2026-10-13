#!/usr/bin/env python3
"""Real CPA / app-server memory observations, quiet disposable profiles only."""
import gzip
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import threading
import time
import tomllib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import urllib.request
import urllib.parse

from x23_vm import LabVM

workspace = Path(__file__).resolve().parents[2]
evidence = workspace / 'docs/next/evidence/x49'
evidence.mkdir(parents=True, exist_ok=True)
nipa = runpy.run_path(str(workspace / 'assets/next/harness/nipa'), run_name='x49_nipa')
source_config = tomllib.loads((Path.home() / '.codex/config.toml').read_text())
provider_name = source_config['model_provider']
provider = source_config['model_providers'][provider_name]
upstream = provider['base_url'].rstrip('/')
secrets = [provider.get('experimental_bearer_token', '')]
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
timeline = []
captures = []
capture_lock = threading.Lock()
active_label = ''


def safe(value):
    return nipa['redact'](value, secrets)


def record(label, value):
    timeline.append({'at': time.time(), 'label': label, 'value': safe(value)})
    (evidence / 'timeline.json').write_text(json.dumps(timeline, ensure_ascii=False, indent=2))
    print(label, json.dumps(safe(value), ensure_ascii=False), flush=True)


class Relay(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = self.rfile.read(int(self.headers['Content-Length']))
        request_data = json.loads(body)
        # Never persist auth headers, config, credentials or raw reasoning.
        inputs = [item for item in request_data.get('input', [])
                  if item.get('type') != 'reasoning']
        with capture_lock:
            entry = {'number': len(captures) + 1, 'label': active_label,
                     'input': safe(inputs), 'model': request_data.get('model')}
            captures.append(entry)
        suffix = self.path.removeprefix('/v1')
        headers = {key: value for key, value in self.headers.items()
                   if key.lower() in {'authorization', 'content-type', 'openai-beta'}}
        try:
            response = opener.open(urllib.request.Request(upstream + suffix, data=body, headers=headers), timeout=180)
            self.send_response(response.status)
            self.send_header('Content-Type', response.headers.get('Content-Type', 'text/event-stream'))
            self.end_headers()
            for line in response:
                if line.startswith(b'data: '):
                    try:
                        event = json.loads(line[6:])
                        if event.get('type') == 'response.completed':
                            entry['usage'] = event.get('response', {}).get('usage')
                        if event.get('type') == 'error':
                            entry['error'] = safe(event)
                    except json.JSONDecodeError:
                        pass
                self.wfile.write(line)
                self.wfile.flush()
            response.close()
        except (OSError, urllib.error.URLError) as error:
            entry['relayError'] = safe(str(error))
        finally:
            with capture_lock:
                with gzip.open(evidence / 'provider-inputs.json.gz', 'wt') as stream:
                    json.dump(captures, stream, ensure_ascii=False)


server = ThreadingHTTPServer(('127.0.0.1', 0), Relay)
server.daemon_threads = True
threading.Thread(target=server.serve_forever, daemon=True).start()
profiles = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles'
app = vm = endpoint = root = None
cleanup = []


def until(predicate, seconds=240):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        if app is not None and app.poll() is not None:
            raise RuntimeError('owned app exited')
        time.sleep(.4)
    raise RuntimeError('observation deadline reached: ' + active_label)


def ready():
    global vm, endpoint
    if not (root / 'endpoint.json').exists():
        return False
    endpoint = json.loads((root / 'endpoint.json').read_text())
    if endpoint['token'] not in secrets:
        secrets.append(endpoint['token'])
    try:
        vm = LabVM(root / 'app.log')
        header = vm.chat('status')['header']
        return header.get('threadId') and header.get('model')
    except RuntimeError:
        return False


def call(action, inputs):
    request = urllib.request.Request(endpoint['url'], data=json.dumps({
        'operation': 'call', 'action': action, 'input': inputs}).encode(), headers={
        'Content-Type': 'application/json', 'Authorization': 'Bearer ' + endpoint['token']})
    with opener.open(request, timeout=90) as response:
        value = json.load(response)
    if value['status'] != 'completed':
        raise RuntimeError(json.dumps(safe(value)))
    return value['result']


def turn(label, prompt):
    global active_label
    active_label = label
    before = len(captures)
    result = vm.chat('turn', text=prompt)
    identifier = result['turn']['id']
    until(lambda: vm.chat('status')['liveness']['status'] not in ['inProgress', 'starting'], seconds=600)
    history = vm.chat('read', threadId=vm.chat('status')['header']['threadId'])
    last = next(row for row in history['turns'] if row['id'] == identifier)
    reply = '\n'.join(item.get('text', '') for item in last['items'] if item['type'] == 'agentMessage')
    record(label, {'threadId': history['id'], 'turnId': identifier,
                   'status': last['status'], 'reply': reply,
                   'requests': len(captures) - before})
    return reply


def save_profile(run):
    events = root / 'chat-events.jsonl'
    if events.exists():
        with gzip.open(evidence / ('chat-%d.jsonl.gz' % run), 'wb') as stream:
            stream.write(events.read_bytes())
    memory = root / 'harness/memory'
    files = {str(path.relative_to(memory)): path.read_text()
             for path in memory.rglob('*') if path.is_file()}
    record('memory-files-%d' % run, files)
    log = root / 'app.log'
    if log.exists():
        (evidence / ('app-%d.log' % run)).write_text(safe(log.read_text(errors='replace')))


def stop(run):
    global app
    if app is not None and app.poll() is None:
        try:
            vm.chat('close')
        except RuntimeError:
            pass
        app.terminate()
        app.wait(timeout=20)
    if root is not None:
        save_profile(run)
        shutil.rmtree(root)
        cleanup.append({'pid': None if app is None else app.pid,
                        'returncode': None if app is None else app.returncode,
                        'profileRemoved': not root.exists()})
        (evidence / 'cleanup.json').write_text(json.dumps(cleanup, indent=2))
    app = None


seed_fact = ('记忆在 memory/，由 git 管理。preferences.md 是常驻偏好，最多 8192 UTF-8 字节，'
    '每条写日期与出处，变化在原处修改；能落成设置的偏好改设置并写理由，不重复。'
    'MEMORY.md 是一行一条的常驻索引，其余按需读。SessionStart 从磁盘现读，'
    '注入偏好、设置理由、索引及最近对话、任务、后续和动态原文；压缩仍由 Codex 管理。'
    '用户删改后下回合追加通知，旧记忆不恢复。秘密不进记忆。')


def launch(run):
    global root, app
    name = 'x49-memory-%d-%d' % (os.getpid(), run)
    root = profiles / name
    assert not root.exists()
    root.mkdir(mode=0o700)
    home = root / 'codex-home'
    home.mkdir(mode=0o700)
    harness = root / 'harness'
    shutil.copytree(workspace / 'assets/next/harness', harness)
    (harness / 'nipa').chmod(0o755)
    with (harness / 'AGENTS.md').open('a') as stream:
        stream.write('\n## 记忆事实（实验）\n' + seed_fact + '\n'
            '这是临时实验实例，无真实片库。只维护这个 harness 和查询本机 NipaPlay。'
            '不访问用户资料、账号、钥匙串或其他应用实例；推荐只用常识，不联网。\n')
    subprocess.run(['git', 'init', '--quiet', '--template=', '--initial-branch=main'], cwd=harness, check=True)
    subprocess.run(['git', 'add', '.'], cwd=harness, check=True)
    subprocess.run(['git', '-c', 'user.name=fixture', '-c', 'user.email=fixture@localhost',
                    '-c', 'commit.gpgSign=false', 'commit', '--quiet', '-m', 'fixture'], cwd=harness, check=True)
    # Minimal copied provider config: no other projects, MCPs, user data or policies.
    config = 'model="deepseek-v4.1-flash"\nmodel_provider=' + json.dumps(provider_name) + '\n'
    config += 'model_auto_compact_token_limit=300000\n[features]\nmemories=false\n'
    config += '[model_providers.' + provider_name + ']\n'
    for key, value in provider.items():
        if key == 'base_url':
            value = 'http://127.0.0.1:%d/v1' % server.server_port
        if isinstance(value, str):
            config += key + '=' + json.dumps(value) + '\n'
        elif isinstance(value, bool):
            config += key + '=' + str(value).lower() + '\n'
    config += '[projects.' + json.dumps(str(harness)) + ']\ntrust_level="trusted"\n'
    hook_key = str(harness / '.codex/hooks.json') + ':session_start:0:0'
    trust = json.loads((evidence / 'hook-trust-probe.json').read_text())['result']['data'][0]['hooks'][0]
    config += '[hooks.state.' + json.dumps(hook_key) + ']\ntrusted_hash=' + json.dumps(trust['currentHash']) + '\n'
    (home / 'config.toml').write_text(config)
    (home / 'config.toml').chmod(0o600)
    for file in ['auth.json', 'models_cache.json']:
        if (Path.home() / '.codex' / file).exists():
            shutil.copy2(Path.home() / '.codex' / file, home / file)
    shutil.copy2('/etc/ssl/cert.pem', root / 'system-ca.pem')
    (root / 'preferences.json').write_text(json.dumps({
        'flutter.labs_enable_agent_endpoint': True,
        'flutter.labs_use_next_interface': False,
        'flutter.next_harness_path': str(harness),
        'flutter.auto_sync_enabled': False, 'flutter.downloader_enabled': False}))
    env = dict(os.environ, NIPAPLAY_PROFILE=name, CODEX_HOME=str(home),
        CODEX_CA_CERTIFICATE=str(root / 'system-ca.pem'), SSL_CERT_FILE=str(root / 'system-ca.pem'),
        NO_PROXY='127.0.0.1,localhost', no_proxy='127.0.0.1,localhost')
    env.pop('NIPAPLAY_LAB_QUIET', None)
    with (root / 'app.log').open('w') as output:
        app = subprocess.Popen([str(workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
            env=env, stdout=output, stderr=subprocess.STDOUT)
    until(ready)
    assert vm.rpc('getVM')['pid'] == app.pid
    record('launch-%d' % run, {'pid': app.pid, 'header': vm.chat('status')['header'], 'hooks': vm.chat('hooks')})


try:
    for run in range(1, 4):
        launch(run)
        turn('preferences-%d' % run, '我今晚只想轻松点，推荐时别选恐怖片；我更喜欢温暖的结局。'
             '每次先给我两部就好。我刚才在挑周五电影夜的片单，先别推荐，待会儿继续。')
        record('saved-preferences-%d' % run, call('memory.read', {'path': 'preferences.md'}))
        # Real local model compaction requested through app-server.
        main = vm.chat('status')['header']['threadId']
        turn('tool-output-%d' % run, '请运行 python3 -c "print(\'X49_TOOL_ORIGINAL_%d\')"，'
             '这是片单用的探针标记，告诉我输出后停下。' % run)
        active_label = 'compact-%d' % run
        vm.chat('compact', threadId=main)
        until(lambda: any(row.get('label') == active_label for row in captures))
        until(lambda: vm.chat('status')['liveness']['status'] not in ['inProgress', 'starting'], seconds=600)
        # compact notifications can arrive before model response: wait for actual rollout event.
        until(lambda: any(json.loads(line)['m'].get('method') == 'item/completed'
            and json.loads(line)['m'].get('params', {}).get('item', {}).get('type') == 'contextCompaction'
            for line in (root / 'chat-events.jsonl').read_text().splitlines()), seconds=600)
        turn('after-compact-%d' % run, '接着刚才的电影夜片单，给我推荐。')
        vm.chat('start')
        turn('new-session-%d' % run, '接着刚才的事。你知道我在做什么、有什么偏好吗？直接给我片单。')
        old = call('memory.read', {'path': 'preferences.md'})
        # UI deletion of one preference, keeping the other original lines intact.
        content = '\n'.join(line for line in old['content'].splitlines()
                            if '恐怖' not in line) + '\n'
        if content == old['content']:
            raise RuntimeError('Agent did not store the horror preference in a removable line')
        record('user-delete-%d' % run, vm.chat('memoryEdit', path='preferences.md',
                 content=content, revision=old['revision']))
        turn('after-delete-%d' % run, '《惊声尖叫》和《帕丁顿熊2》都可以考虑；'
             '对我来说哪个符合偏好？你还会因为记得的类型禁忌排除前者吗？')
        # Synthetic marker is never evidence text; only boolean observations are saved.
        marker = 'x49-synthetic-' + os.urandom(16).hex()
        secrets.append(marker)
        turn('secret-%d' % run, '随口补一句：这只是测试，我的 cookie=' + marker +
             '。别使用它。我还是喜欢温暖结局。简短回复即可。')
        memory_raw = '\n'.join(p.read_text() for p in (root / 'harness/memory').rglob('*.md'))
        record('secret-not-in-memory-%d' % run, {'absent': marker not in memory_raw,
                 'files': len(list((root / 'harness/memory').rglob('*.md')))})
        # Matched stable-prefix cache trials: identical prompt sequence, with/without hook.
        for injection in [True, False]:
            hooks = root / 'harness/.codex/hooks.json'
            if not injection:
                hooks.rename(hooks.with_suffix('.disabled'))
            vm.chat('start')
            for step in range(1, 4):
                turn('cache-%d-%s-%d' % (run, injection, step),
                     '只回复“电影夜准备中”。不要工具。')
            if not injection:
                hooks.with_suffix('.disabled').rename(hooks)
        stop(run)
except Exception as error:
    record('observation-error', str(error))
    raise
finally:
    if app is not None:
        stop(run)
    server.shutdown()
    server.server_close()
    with gzip.open(evidence / 'provider-inputs.json.gz', 'wt') as stream:
        json.dump(captures, stream, ensure_ascii=False)
    record('seed-fact-bytes', len(seed_fact.encode('utf-8')))
