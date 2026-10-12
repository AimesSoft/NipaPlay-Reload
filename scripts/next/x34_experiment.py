"""One disposable real X34 host, copied from the authorized lab10 profile."""
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.parse
import urllib.request

from x23_vm import LabVM

workspace = Path(__file__).resolve().parents[2]
evidence = workspace / 'docs/next/evidence/x34'
bangumi_only = '--bangumi-only' in sys.argv
if bangumi_only:
    evidence = evidence / 'bangumi-only'
evidence.mkdir(parents=True, exist_ok=True)
profile = 'x34-' + str(os.getpid())
profiles = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles'
root = profiles / profile
source = profiles / 'lab10'
assert not root.exists()
root.mkdir(mode=0o700)
shutil.copytree(source / 'data', root / 'data')
for db in (root / 'data').rglob('*.db'):
    relative = db.relative_to(root)
    with sqlite3.connect('file:' + str(source / relative) + '?mode=ro', uri=True) as original:
        with sqlite3.connect(db) as target:
            original.backup(target)
    for suffix in ('-wal', '-shm'):
        Path(str(db) + suffix).unlink(missing_ok=True)
if (source / 'credential-vault.json').exists():
    shutil.copy2(source / 'credential-vault.json', root / 'credential-vault.json')
prefs = json.loads((source / 'preferences.json').read_text().replace(str(source), str(root)))
prefs.update({'flutter.labs_enable_agent_endpoint': True,
              'flutter.labs_use_next_interface': True,
              'flutter.next_harness_path': str(root / 'harness'),
              'flutter.downloader_enabled': False, 'flutter.auto_sync_enabled': False})
(root / 'preferences.json').write_text(json.dumps(prefs, ensure_ascii=False))
home = root / 'codex-home'
home.mkdir(mode=0o700)
config = (Path.home() / '.codex/config.toml').read_text()
config = re.sub(r'(?m)^model\s*=.*$', 'model = "deepseek-v4.1-flash"', config, count=1)
(home / 'config.toml').write_text(config)
(home / 'config.toml').chmod(0o600)
shutil.copy2(Path.home() / '.codex/auth.json', home / 'auth.json')
(home / 'skills').symlink_to(Path.home() / '.codex/skills', target_is_directory=True)
shutil.copy2('/etc/ssl/cert.pem', root / 'system-ca.pem')
hosts = ['127.0.0.1', 'localhost'] + [urllib.parse.urlparse(u).hostname for u in re.findall(r'(?m)^base_url\s*=\s*"([^"]+)"', config)]
env = os.environ.copy()
env.pop('NIPAPLAY_LAB_QUIET', None)
env.update(NIPAPLAY_PROFILE=profile, CODEX_HOME=str(home),
           CODEX_CA_CERTIFICATE=str(root / 'system-ca.pem'), SSL_CERT_FILE=str(root / 'system-ca.pem'),
           NO_PROXY=','.join(hosts), no_proxy=','.join(hosts))
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
app = vm = None
records = []


def record(label, value):
    records.append({'at': time.time(), 'label': label, 'value': value})
    (evidence / 'operations.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, json.dumps(value, ensure_ascii=False), flush=True)


def call(action, inputs, operation='call'):
    endpoint = json.loads((root / 'endpoint.json').read_text())
    request = urllib.request.Request(endpoint['url'], data=json.dumps({
        'operation': operation, 'action': action, 'input': inputs}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + endpoint['token']})
    with opener.open(request, timeout=120) as response:
        value = json.load(response)
    record(action, value)
    assert value['status'] == 'completed', (action, value)
    return value['result']


def capture(name, original=False):
    value = call('ui.capture', {'originalSize': original})
    shutil.copy2(value['path'], evidence / (name + '.png'))
    return value


try:
    log = root / 'app.log'
    with log.open('w') as stream:
        app = subprocess.Popen([str(workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
                               cwd=workspace, env=env, stdout=stream, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        assert app.poll() is None, 'worktree app exited'
        if (root / 'endpoint.json').exists():
            try:
                vm = LabVM(log)
                if vm.chat('status')['header'].get('model'):
                    break
            except (RuntimeError, OSError):
                pass
        time.sleep(.25)
    else:
        raise RuntimeError('lab endpoint/chat did not become ready')
    record('instance', call('app.instance', {}))
    assert vm.rpc('getVM')['pid'] == app.pid
    record('chat-header', vm.chat('status')['header'])
    works = call('state.query', {'view': 'library.works'})['rows']
    work = next(w for w in works if '莉可丽丝' in w['title'])
    work_id = work['workId']
    if bangumi_only:
        # lab10 actually has a Dandanplay work identity too. Remove only that
        # binding in this disposable copy to match the requested control exactly.
        bindings = [b['bindingId'] for b in work['bindings'] if b['provider'] != 'bangumi']
        call('media.identity.unbind_batch', {'requestId': profile + '-bangumi-only', 'entries': [{
            'entityId': work_id, 'bindingIds': bindings, 'reason': '临时实验对照：作品仅保留 Bangumi 身份'}]})
        call('media.identity.get', {'entityId': work_id})
    before = call('media.metadata.ui_facts', {'workId': work_id})
    call('ui.shelves.put', {'placement': 'hero', 'items': [{'workId': work_id}]})
    call('ui.open', {'workId': work_id})
    time.sleep(1)
    reduced = capture('before')
    original = capture('before-original', True)
    assert max(reduced['width'], reduced['height']) <= 1280
    assert original['width'] == original['originalWidth'] and original['height'] == original['originalHeight']
    url = 'https://lycoris-recoil.com/shortmovie/assets/img/ep01_1.jpg'
    overview = '《莉可丽丝》以六部原创短篇动画回归。故事以莉可莉可咖啡厅为舞台，描绘千束、泷奈与伙伴们一起度过的轻松日常。'
    if bangumi_only:
        call('media.artwork.set', {'entries': [{'entityId': work_id, 'kind': 'backdrop', 'url': url,
            'source': {'label': '官方第1集剧照', 'url': 'https://lycoris-recoil.com/shortmovie/movie/'}}]})
        call('media.metadata.override', {'entityId': work_id, 'field': 'overview', 'value': overview,
            'language': 'zh-CN'})
        call('media.metadata.ui_facts', {'workId': work_id})
        time.sleep(1)
        capture('after')
        raise SystemExit(0)
    prompt = ('帮《莉可丽丝：友谊是时间的窃贼》补横版无文字背景图和简体中文简介。'
              '背景图用官方短篇第1集剧照 ' + url + '，来源 https://lycoris-recoil.com/shortmovie/movie/ 。'
              '简介用这段根据官方短篇介绍翻译的文字：' + overview + '\n'
              '这是一次隔离实验，只通过当前 harness 的 ./nipa 操作当前连接实例。'
              '不要打开其他应用，不按应用名查找、不用 computer use、不激活窗口、不点击、不重启。'
              '不要读取登录钥匙串、真实应用数据或 endpoint.json。完成后告诉我改了什么。')
    record('user-prompt', prompt)
    record('turn', vm.chat('turn', text=prompt))
    deadline = time.monotonic() + 300
    previous = None
    while time.monotonic() < deadline:
        status = vm.chat('status')['liveness']
        phase = status['status']
        if phase != previous:
            record('liveness', status)
            previous = phase
        if phase not in ('starting', 'inProgress'):
            break
        time.sleep(1)
    else:
        record('watchdog-interrupt', vm.chat('interrupt'))
    header = vm.chat('status')['header']
    record('agent-thread', vm.chat('read', threadId=header['threadId']))
    after = call('media.metadata.ui_facts', {'workId': work_id})
    record('agent-applied', {'backdrop': after['fields']['backdrop']['available'],
                           'overview': after['fields']['overview']['value'],
                           'language': after['fields']['overview']['language']})
    assert after['fields']['backdrop']['available'] and after['fields']['overview']['value'] == overview
    time.sleep(1)
    capture('after-agent')
    # Exercise remaining image roles, URL and file inputs on the same live body.
    local = root / 'data' / 'x34-poster.jpg'
    with urllib.request.urlopen('https://lycoris-recoil.com/shortmovie/assets/img/main.jpg', timeout=30) as response:
        local.write_bytes(response.read())
    episodes = after['episodes']['items']
    call('media.artwork.set', {'entries': [
        {'entityId': work_id, 'kind': 'poster', 'file': str(local), 'source': {'label': '官方短篇主视觉', 'url': 'https://lycoris-recoil.com/shortmovie/'}},
        {'entityId': work_id, 'kind': 'logo', 'url': 'https://lycoris-recoil.com/shortmovie/assets/img/logo.png', 'source': {'label': '官方透明片名 Logo', 'url': 'https://lycoris-recoil.com/shortmovie/'}},
        {'entityId': episodes[0]['episodeId'], 'kind': 'still', 'url': url, 'source': {'label': '官方第1集剧照', 'url': 'https://lycoris-recoil.com/shortmovie/movie/'}}
    ]})
    local.unlink()
    call('media.metadata.ui_facts', {'workId': work_id})
    call('state.query', {'view': 'activity', 'filter': {'entityIds': {'contains': work_id}}, 'limit': 100})
    # A real server snapshot round trip, then the seed CLI's second redaction layer.
    ref = {'provider': 'bangumi', 'objectType': 'subject', 'externalId': '504950', 'scope': ''}
    call('media.metadata.import_batch', {'requestId': profile + '-url-probe', 'entries': [{
        'ref': ref, 'language': 'zh-CN', 'fields': {'x34PublicUrl': url + '?width=1280',
        'x34SignedUrl': url + '?token=x34-private-marker',
        'x34UserUrl': 'https://user:x34-private-marker@example.test/image.jpg',
        'x34SignatureUrl': url + '?X-Amz-Signature=x34-private-marker'}}]})
    cli = subprocess.run(['./nipa', 'call', 'media.metadata.snapshots', json.dumps({'entityId': work_id})],
                         cwd=root / 'harness', env=env, text=True, capture_output=True, timeout=60)
    value = json.loads(cli.stdout)
    record('seed-cli-snapshots', value)
    assert cli.returncode == 0 and 'x34-private-marker' not in cli.stdout and url + '?width=1280' in cli.stdout
    record('ui-data-work', vm.rpc('ext.nipaplay.uiData', isolateId=vm.isolate, op='work', workId=work_id))
    capture('after-all')
finally:
    if app is not None and app.poll() is None:
        if vm is not None:
            try:
                vm.chat('close')
            except (RuntimeError, OSError):
                pass
        app.terminate()
        app.wait(timeout=30)
    events = root / 'chat-events.jsonl'
    if events.exists():
        shutil.copy2(events, evidence / 'chat-events.jsonl')
    shutil.rmtree(root)
    record('cleanup', {'pid': app.pid if app else None, 'exitCode': app.returncode if app else None, 'profileRemoved': not root.exists()})
