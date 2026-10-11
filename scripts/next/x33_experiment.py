"""Disposable X33 instance; no activation, pixel input, real data or credentials."""
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import threading
import time
import urllib.request
from http.server import ThreadingHTTPServer
from x23_vm import LabVM
from x33_provider import Provider

workspace = Path(__file__).resolve().parents[2]
evidence = workspace/'docs/next/evidence/x33'
evidence.mkdir(parents=True, exist_ok=True)
profile = 'x33-'+str(os.getpid())
root = Path.home()/'Library/Application Support/NipaPlay/LabProfiles'/profile
assert not root.exists()
root.mkdir(mode=0o700)
server = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
threading.Thread(target=server.serve_forever, daemon=True).start()
home = root/'codex-home'
home.mkdir(mode=0o700)
(home/'config.toml').write_text(f'''model = "deepseek-v4.1-flash"
model_provider = "x33-fixture"
[model_providers.x33-fixture]
name = "实验模型"
base_url = "http://127.0.0.1:{server.server_port}/v1"
wire_api = "responses"
requires_openai_auth = false
''')
(home/'config.toml').chmod(0o600)
shutil.copy2('/etc/ssl/cert.pem', root/'system-ca.pem')
media = root/'data/fixture'
media.mkdir(parents=True)
env = os.environ.copy()
env.pop('NIPAPLAY_LAB_QUIET', None)
env.update(NIPAPLAY_PROFILE=profile, CODEX_HOME=str(home),
           CODEX_CA_CERTIFICATE=str(root/'system-ca.pem'), SSL_CERT_FILE=str(root/'system-ca.pem'),
           NO_PROXY='127.0.0.1,localhost', no_proxy='127.0.0.1,localhost')
prefs = {'flutter.labs_enable_agent_endpoint': True, 'flutter.downloader_enabled': False,
         'flutter.labs_use_next_interface': False, 'flutter.skip_danmaku_matching': True,
         'flutter.auto_sync_enabled': False, 'flutter.nipaplay_scanned_folders': [str(media)]}
(root/'preferences.json').write_text(json.dumps(prefs))
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
records, apps = [], []
app = vm = endpoint = None


def record(label, value):
    records.append({'label': label, 'value': value})
    (evidence/'operations.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, json.dumps(value, ensure_ascii=False), flush=True)


def until(predicate, seconds=120):
    deadline = time.monotonic()+seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        assert app.poll() is None, 'app exited'
        time.sleep(.25)
    raise RuntimeError('experiment timeout')


def call(action, inputs):
    request = urllib.request.Request(endpoint['url'], data=json.dumps({'operation': 'call', 'action': action, 'input': inputs}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer '+endpoint['token']})
    with opener.open(request, timeout=60) as response:
        value = json.load(response)
    record(action, value)
    assert value['status'] == 'completed', (action, value)
    return value['result']


def launch(index):
    global app, vm, endpoint
    (root/'endpoint.json').unlink(missing_ok=True)
    log = evidence/f'app-{index}.log'
    with log.open('w') as stream:
        app = subprocess.Popen([str(workspace/'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
            cwd=workspace, env=env, stdout=stream, stderr=subprocess.STDOUT)
    apps.append(app)
    def ready():
        global vm, endpoint
        if not (root/'endpoint.json').exists(): return False
        try:
            endpoint = json.loads((root/'endpoint.json').read_text())
            vm = LabVM(log)
            header = vm.chat('status')['header']
            return header.get('threadId') and header.get('model')
        except (OSError, RuntimeError): return False
    until(ready)
    record('instance', {'pid': app.pid, 'vmPid': vm.rpc('getVM')['pid'], 'profile': profile})


def stop():
    if app is not None and app.poll() is None:
        vm.chat('close')
        app.terminate()
        app.wait(timeout=30)


def ui(op, **params):
    return vm.rpc('ext.nipaplay.uiData', isolateId=vm.isolate, op=op, **params)


def capture(name):
    value = call('ui.capture', {})
    shutil.copy2(value['path'], evidence/(name+'.png'))


try:
    launch(0)
    main = vm.chat('status')['header']['threadId']
    turns = []
    for label in ['第一轮', '第二轮', '第三轮']:
        if label == '第二轮': vm.chat('start')
        if label == '第三轮': vm.chat('resume', threadId=main)
        thread = vm.chat('status')['header']['threadId']
        turn = vm.chat('turn', text=label+'，执行命令后告诉我结果。')['turn']['id']
        until(lambda: vm.chat('status')['liveness']['status'] == 'completed')
        turns.append((thread, turn))
        record('turn', {'threadId': thread, 'turnId': turn, 'liveness': vm.chat('status')['liveness']})
    stop()
    # Existing disposable integration XML, with real viewer comments; no user data.
    import hashlib
    import xml.etree.ElementTree as ET
    source = Path(os.environ.get('X33_COMMENTS', '/tmp/danmaku-integration.HbRGnM/长安十二时辰 S01E01.xml'))
    comments = media/'episode-1.xml'
    shutil.copy2(source, comments)
    source_items = ET.parse(comments).findall('d')
    record('existing-real-cache', {'source': str(source), 'sha256': hashlib.sha256(comments.read_bytes()).hexdigest(),
        'entries': len(source_items), 'openingEntries': sum(float(d.get('p').split(',')[0]) < 180 for d in source_items)})
    title, anime_id, episode_id = '长安十二时辰', 33001, 3300101
    fixture = media/'episode-1.mkv'
    fixture.write_bytes(b'X33 detail fixture; not video\n')
    schema = (workspace/'lib/models/watch_history_database.dart').read_text().split('CREATE TABLE watch_history(', 1)[1].split("''');", 1)[0]
    with sqlite3.connect(root/'data/watch_history.db') as db:
        db.execute('CREATE TABLE IF NOT EXISTS watch_history('+schema)
        db.execute('PRAGMA user_version=2')
        db.execute('INSERT INTO watch_history(file_path,anime_name,episode_title,anime_id,episode_id,watch_progress,last_position,duration,last_watch_time,is_from_scan) VALUES(?,?,?,?,?,?,?,?,?,?)',
            (str(fixture), title, '第 1 集', anime_id, episode_id, 0, 0, 2700000, '2026-10-12T00:00:00', 1))
    current_prefs = json.loads((root/'preferences.json').read_text())
    anime = {'animeId': anime_id, 'animeTitle': title, 'id': anime_id, 'name': title, 'name_cn': title, 'imageUrl': '',
        'summary': '长安城里的故事开始了。', 'totalEpisodes': 1,
        'episodes': [{'episodeId': episode_id, 'episodeTitle': '第 1 集'}]}
    current_prefs[f'flutter.bangumi_detail_{anime_id}'] = json.dumps({'timestamp': int(time.time()*1000), 'animeDetail': anime}, ensure_ascii=False)
    (root/'preferences.json').write_text(json.dumps(current_prefs, ensure_ascii=False))
    launch(1)
    assert vm.chat('status')['header']['threadId'] == main
    for thread, turn in turns:
        process = call('chat.turn.process', {'threadId': thread, 'turnId': turn})
        assert process['found']
        commands = [v for v in process['process']['items'] if v['type'] == 'commandExecution']
        assert len(commands) == 1
        assert 'synthetic-private-value' not in json.dumps(process)
    for thread in dict.fromkeys(thread for thread, _ in turns):
        history = vm.chat('read', threadId=thread)
        record('history-rebuilt', [{'threadId': thread, 'turnId': t['id'], 'commands': len([i for i in t['items'] if i['type'] == 'commandExecution']),
            'summaries': len([i for i in t['items'] if i['type'] == 'reasoning'])} for t in history['turns']])
    call('media.library.import_history', {})
    works = call('state.query', {'view': 'library.works'})['rows']
    work_id = works[0]['workId']
    episodes = ui('episodes', workId=work_id)
    call('danmaku.import', {'filePath': str(comments), 'platform': 'bilibili', 'platformVideoId': 'x33-existing-changan-episode-1',
        'entityId': episodes[0]['episodeId'], 'note': '已有临时集成实验的第一集真实弹幕缓存'})
    call('danmaku.tracks', {'entityId': episodes[0]['episodeId']})
    work = ui('work', workId=work_id)
    record('real-opening-comments', {'workId': work_id, 'title': work['title'], 'danmaku': work['danmaku']})
    assert work['danmaku']
    with sqlite3.connect(root/'data/next/next.db') as db:
        rows = db.execute('SELECT * FROM danmaku_cache_chunks').fetchall()
        record('cache-chunks', {'count': len(rows)})
    call('settings.set', {'key': 'next.heroOpeningSeconds', 'value': 120})
    record('two-minute-comments', ui('work', workId=work_id)['danmaku'])
    call('settings.set', {'key': 'labs_use_next_interface', 'value': True})
    time.sleep(1)
    opened = call('ui.open', {'workId': work_id})
    assert opened['interface'] == 'next'
    time.sleep(1)
    capture('next-detail')
    call('settings.set', {'key': 'labs_use_next_interface', 'value': False})
    time.sleep(1)
    opened = call('ui.open', {'entityId': work_id})
    assert opened['interface'] == 'classic'
    time.sleep(1)
    capture('classic-detail')
finally:
    try:
        stop()
    finally:
        server.shutdown()
        server.server_close()
        if (root/'chat-events.jsonl').exists():
            shutil.copy2(root/'chat-events.jsonl', evidence/'chat.jsonl')
        shutil.rmtree(root)
        record('cleanup', {'pids': [p.pid for p in apps], 'processesExited': all(p.poll() is not None for p in apps), 'profileRemoved': not root.exists()})
