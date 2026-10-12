#!/usr/bin/env python3
"""Three read-only XML copies in an owned quiet worktree instance."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
from x23_vm import LabVM

workspace = Path(__file__).resolve().parents[2]
evidence = workspace / 'docs/next/evidence/x42'
mode = sys.argv[1] if sys.argv[1:] else 'files'
assert mode in ('files', 'refresh-only', 'episode-refresh')
refresh_only = mode != 'files'
profile = f'x42-{mode}-{os.getpid()}'
root = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
assert not root.exists()
root.mkdir(parents=True, mode=0o700)
data = root / 'data/next'
media = root / 'data/media'
media.mkdir(parents=True)
home = root / 'codex-home'
home.mkdir(mode=0o700)
# This is a direct capability experiment, with no model conversation or auth.
(home / 'config.toml').write_text('model = "deepseek-v4.1-flash"\n')
shutil.copy2('/etc/ssl/cert.pem', root / 'system-ca.pem')
harness = root / 'harness'
shutil.copytree(workspace / 'assets/next/harness', harness)
(harness / 'nipa').chmod(0o755)
inputs = harness / 'records'
inputs.mkdir()
prefs = {
    'flutter.labs_enable_agent_endpoint': True,
    'flutter.labs_use_next_interface': True,
    'flutter.next_harness_path': str(harness),
    'flutter.auto_sync_enabled': False,
    'flutter.downloader_enabled': False,
    'flutter.player_volume': 0.0,
    'flutter.danmaku_auto_load_strategy': 'disabled',
    'flutter.skip_danmaku_matching': True,
    'flutter.web_server_auto_start': False,
    'flutter.remote_control_receiver_enabled': False,
    'flutter.auto_check_update': False,
}
(root / 'preferences.json').write_text(json.dumps(prefs))
env = dict(os.environ, NIPAPLAY_PROFILE=profile, CODEX_HOME=str(home),
           CODEX_CA_CERTIFICATE=str(root / 'system-ca.pem'),
           SSL_CERT_FILE=str(root / 'system-ca.pem'),
           NO_PROXY='127.0.0.1,localhost,::1', no_proxy='127.0.0.1,localhost,::1')
for key in ('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy',
            'https_proxy', 'all_proxy', 'NIPAPLAY_LAB_QUIET'):
    env.pop(key, None)
executable = workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay'
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
records = []
app = stream = vm = endpoint = None
secrets = []
starts = []


def clean(v):
    if isinstance(v, str):
        for s in secrets:
            v = v.replace(s, '[REDACTED]')
        return v
    if isinstance(v, dict): return {k: clean(x) for k, x in v.items()}
    if isinstance(v, list): return [clean(x) for x in v]
    return v


def record(label, value):
    records.append({'label': label, 'value': clean(value)})
    (evidence / (f'operations-{mode}.json' if refresh_only else 'operations.json')).write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, json.dumps(clean(value), ensure_ascii=False), flush=True)
    return value


def call(action, inputs=None, save=True):
    request = urllib.request.Request(endpoint['url'], data=json.dumps({
        'operation': 'call', 'action': action, 'input': inputs or {}}).encode(),
        headers={'Content-Type': 'application/json',
                 'Authorization': 'Bearer ' + endpoint['token']})
    with opener.open(request, timeout=180) as response:
        value = json.load(response)
    if save: record(action, {'input': inputs, **value})
    assert value['status'] == 'completed', clean(value)
    return value['result']


def wait_job(job):
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        v = call('task.get', {'jobId': job['jobId']}, save=False)['job']
        if v['state'] in ('succeeded', 'failed', 'cancelled'):
            record('job', v)
            assert v['state'] == 'succeeded'
            return v
        time.sleep(.3)
    raise TimeoutError('Owned experiment job')


def start(phase):
    global app, stream, vm, endpoint
    (root / 'endpoint.json').unlink(missing_ok=True)
    log = root / f'{phase}.log'
    stream = log.open('w')
    started = time.monotonic()
    app = subprocess.Popen([str(executable)], cwd=workspace, env=env,
                           stdout=stream, stderr=subprocess.STDOUT)
    starts.append(app.pid)
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        assert app.poll() is None, 'Owned executable exited'
        if (root / 'endpoint.json').exists():
            endpoint = json.loads((root / 'endpoint.json').read_text())
            try:
                vm = LabVM(log)
                if vm.rpc('ext.nipaplay.uiData', isolateId=vm.isolate,
                          op='observations'): break
            except (RuntimeError, OSError): pass
        time.sleep(.3)
    else: raise TimeoutError('Owned experiment startup')
    secrets.append(endpoint['token'])
    assert vm.rpc('getVM')['pid'] == app.pid
    record('instance-' + phase, {'profile': profile, 'pid': app.pid,
           'executable': str(executable), 'startupSeconds': time.monotonic() - started})


def stop():
    global app, stream
    if app is not None and app.poll() is None:
        if vm is not None:
            try: vm.chat('close')
            except (RuntimeError, OSError): pass
        app.terminate()
        try: app.wait(timeout=25)
        except subprocess.TimeoutExpired:
            app.kill(); app.wait(timeout=10)
    if stream: stream.close()


def database():
    return sqlite3.connect(data / 'next.db')


def snapshots(label):
    with sqlite3.connect((data / 'next.db').as_uri() + '?mode=ro', uri=True) as db:
        db.row_factory = sqlite3.Row
        rows = [dict(r) for r in db.execute('SELECT * FROM danmaku_cache_chunks ORDER BY cache_key')]
    for r in rows:
        p = data / r['file_path']
        content = p.read_bytes()
        assert p.name == hashlib.sha256(content).hexdigest() + '.json'
        assert len(json.loads(content)) == r['entry_count']
        assert r['payload'] == '[]'
    return record(label, {'rows': rows, 'databaseBytes': (data / 'next.db').stat().st_size,
                         'fileBytes': sum(p.stat().st_size for p in (data / 'danmaku').glob('*.json')),
                         'files': len(list((data / 'danmaku').glob('*.json')))})


try:
    if refresh_only:
        video = media / 'refresh.mp4'
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi',
                        '-i', 'color=c=0x173652:s=320x180:r=1', '-t', '300',
                        '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
                        str(video)], check=True)
        start('refresh-only')
        call('media.library.roots.add', {'paths': [str(media)]})
        target = {'path': str(video)}
        if mode == 'episode-refresh':
            wait_job(call('media.library.scan', {'root': str(media), 'requestId': profile})['job'])
            files = call('state.query', {'view': 'library.files', 'limit': 20})['rows']
            stop()
            with database() as db:
                db.execute('INSERT INTO media_entities(id,kind,attributes) VALUES(?,?,?)',
                           ('x42-work', 'work', '{"title":"Episode refresh"}'))
                db.execute('INSERT INTO media_entities(id,kind,parent_id,attributes) VALUES(?,?,?,?)',
                           ('x42-release', 'release', 'x42-work', '{"season":1}'))
                db.execute('INSERT INTO media_entities(id,kind,parent_id,attributes) VALUES(?,?,?,?)',
                           ('x42-episode', 'episode', 'x42-release', '{"number":"1","season":1}'))
                db.execute('INSERT INTO media_file_episodes(file_id,episode_id,relation,ordinal) VALUES(?,?,?,?)',
                           (files[0]['fileId'], 'x42-episode', 'contains', 1))
            start('episode-refresh')
            target = {'entityId': 'x42-episode'}
        pool = inputs / 'pool.json'
        def rows(n):
            pool.write_text(json.dumps([{'sourceTimeMs': 1000 + i * 1000,
                'text': f'刷新验证 {i}', 'mode': 1, 'colorRgb': 16777215}
                for i in range(n)], ensure_ascii=False))
        rows(1)
        first = call('danmaku.import', {**target, 'filePath': str(pool),
                              'platform': 'fixture', 'platformVideoId': 'refresh'})
        call('playback.open', {'path': str(video)})
        deadline = time.monotonic() + 90
        while time.monotonic() < deadline:
            tracks = call('playback.tracks', save=False)
            if any(t['kind'] == 'danmaku' and t['count'] == 1 for t in tracks['tracks']): break
            time.sleep(.3)
        else: raise TimeoutError('Initial refresh fixture mount')
        record('refresh-first-loaded', tracks)
        if mode == 'episode-refresh':
            call('playback.set_paused', {'paused': True})
            call('danmaku.export', {'bindingId': first['bindingId'],
                'path': str(media / 'export.json'), 'view': 'raw'})
        rows(2)
        result = call('danmaku.import', {**target, 'filePath': str(pool),
                                       'platform': 'fixture', 'platformVideoId': 'refresh'})
        record('refresh-current-state', call('playback.state', save=False))
        record('refresh-second-loaded', call('playback.tracks', save=False))
        assert result['loaded']
        stop()
        snapshots('refresh-files')
        raise SystemExit(0)
    source = Path('/Volumes/Media/长安十二时辰')
    xmls = sorted(source.rglob('*.xml'))[:3]
    assert len(xmls) == 3
    sources = []
    for i, path in enumerate(xmls, 1):
        content = path.read_bytes()
        x = ET.fromstring(content)
        copied = inputs / f'episode-{i}.xml'
        copied.write_bytes(content)
        sources.append({'path': str(path), 'copy': str(copied), 'bytes': len(content),
                        'sha256': hashlib.sha256(content).hexdigest(),
                        'count': len(x.findall('d')), 'videoId': x.findtext('chatid')})
    record('read-only-sources', sources)
    # Synthetic videos avoid reading or copying any episode video from SMB.
    video = media / 'episode-1.mp4'
    subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-f', 'lavfi',
                    '-i', 'color=c=0x173652:s=320x180:r=1', '-t', '3000',
                    '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
                    str(video)], check=True)
    for i in (2, 3): shutil.copy2(video, media / f'episode-{i}.mp4')
    start('bootstrap')
    call('media.library.roots.add', {'paths': [str(media)]})
    wait_job(call('media.library.scan', {'root': str(media), 'requestId': profile + '-scan'})['job'])
    files = call('state.query', {'view': 'library.files', 'limit': 20})['rows']
    stop()
    # Synthetic identity fixture only, in a stopped owned profile.
    with database() as db:
        db.execute('INSERT INTO media_entities(id,kind,attributes) VALUES(?,?,?)',
                   ('x42-work', 'work', json.dumps({'title': 'X42 三集弹幕存储实验'})))
        db.execute('INSERT INTO media_entities(id,kind,parent_id,attributes) VALUES(?,?,?,?)',
                   ('x42-release', 'release', 'x42-work', json.dumps({'season': 1})))
        for i in range(1, 4):
            fid = next(f['fileId'] for f in files if f['locator'] == str(media / f'episode-{i}.mp4'))
            db.execute('INSERT INTO media_entities(id,kind,parent_id,attributes) VALUES(?,?,?,?)',
                       (f'x42-episode-{i}', 'episode', 'x42-release',
                        json.dumps({'number': str(i), 'season': 1, 'title': f'第{i}集'})))
            db.execute('INSERT INTO media_file_episodes(file_id,episode_id,relation,ordinal) VALUES(?,?,?,?)',
                       (fid, f'x42-episode-{i}', 'contains', i))
    start('import')
    imported = []
    for i, s in enumerate(sources, 1):
        r = call('danmaku.import', {'entityId': f'x42-episode-{i}',
                 'filePath': s['copy'], 'platform': 'youku', 'platformVideoId': s['videoId']})
        assert r['count'] == s['count']
        imported.append(r)
    before = snapshots('imported-files')
    call('state.query', {'view': 'danmaku.datasets', 'limit': 20})
    call('media.metadata.ui_facts', {'workId': 'x42-work'})
    heat = vm.rpc('ext.nipaplay.uiData', isolateId=vm.isolate, op='episodes', workId='x42-work')
    record('heat-before', heat)
    assert all(len(e['heat']) == 60 for e in heat)
    record('hero-comments', vm.rpc('ext.nipaplay.uiData', isolateId=vm.isolate,
                                 op='work', workId='x42-work')['danmaku'])
    for s in sources: Path(s['copy']).unlink()
    record('deleted-input-copies', {'deleted': len(sources),
                                  'allMissing': all(not Path(s['copy']).exists() for s in sources)})
    call('playback.open', {'path': str(video)})
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        tracks = call('playback.tracks', save=False)
        danmaku = [t for t in tracks['tracks'] if t['kind'] == 'danmaku']
        if danmaku and danmaku[0]['count'] == sources[0]['count']: break
        time.sleep(.3)
    else: raise TimeoutError('Danmaku playback load')
    record('playback-after-deleting-copies', tracks)
    call('playback.set_paused', {'paused': True})
    export = call('danmaku.export', {'bindingId': imported[0]['bindingId'],
                  'path': str(media / 'export.json'), 'view': 'raw'})
    assert export['count'] == sources[0]['count']
    old = next(r for r in before['rows'] if r['entry_count'] == sources[0]['count'])
    refresh = inputs / 'refresh.json'
    refresh.write_text(json.dumps([{'sourceTimeMs': 1000, 'text': '刷新后的弹幕',
                                   'mode': 1, 'colorRgb': 16777215}], ensure_ascii=False))
    call('danmaku.import', {'entityId': 'x42-episode-1', 'filePath': str(refresh),
                          'platform': 'youku', 'platformVideoId': sources[0]['videoId']})
    assert not (data / old['file_path']).exists()
    record('refresh-old-file-cleanup', {'oldFile': old['file_path'], 'exists': False})
    record('playback-refreshed', call('playback.tracks', save=False))
    snapshots('refreshed-files')
    stop()
    # Recreate exact old rows from the already verified serialized files. No reimport.
    with database() as db:
        rows = list(db.execute('SELECT cache_key,chunk_index,file_path,entry_count FROM danmaku_cache_chunks'))
        legacy_counts = {key: count for key, _, _, count in rows}
        hashes = {key: hashlib.sha256((data / p).read_bytes()).hexdigest() for key, _, p, _ in rows}
        for key, index, p, _ in rows:
            db.execute('UPDATE danmaku_cache_chunks SET payload=? WHERE cache_key=? AND chunk_index=?',
                       ((data / p).read_text(), key, index))
        for column in ('file_path', 'entry_count', 'byte_count', 'storage_kind'):
            db.execute('ALTER TABLE danmaku_cache_chunks DROP COLUMN ' + column)
        db.execute('DROP TABLE danmaku_storage_state')
        db.execute('PRAGMA user_version=14')
        db.execute('DELETE FROM ui_cache')
    shutil.rmtree(data / 'danmaku')
    legacy_size = (data / 'next.db').stat().st_size
    record('legacy-database-before', {'bytes': legacy_size, 'counts': legacy_counts,
                                    'totalCount': sum(legacy_counts.values()), 'contentHashes': hashes})
    start('migration')
    migrated = snapshots('migrated-files')
    assert {r['cache_key']: r['entry_count'] for r in migrated['rows']} == legacy_counts
    assert all(Path(r['file_path']).stem == hashes[r['cache_key']] for r in migrated['rows'])
    assert migrated['databaseBytes'] < legacy_size
    call('media.metadata.ui_facts', {'workId': 'x42-work'})
    record('heat-after-migration', vm.rpc('ext.nipaplay.uiData', isolateId=vm.isolate,
                                        op='episodes', workId='x42-work'))
    record('migration-comparison', {'beforeBytes': legacy_size,
           'afterBytes': migrated['databaseBytes'], 'beforeCount': sum(legacy_counts.values()),
           'afterCount': sum(r['entry_count'] for r in migrated['rows']),
           'allContentHashesUnchanged': True})
    record('prune-imports-preserved', call('danmaku.cache_prune', {'maxBytes': 0}, save=False))
    snapshots('after-prune')
    stop()
    record('sources-unchanged', {'allHashesMatch': all(
        hashlib.sha256(Path(s['path']).read_bytes()).hexdigest() == s['sha256'] for s in sources)})
finally:
    stop()
    shutil.rmtree(root)
    record('cleanup', {'profileRemoved': not root.exists(), 'ownedPids': starts,
           'lastProcessExited': app is None or app.poll() is not None})
