#!/usr/bin/env python3
"""System capabilities in one owned, quiet profile, without a model host."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import urllib.request

workspace = Path(__file__).resolve().parents[2]
evidence = workspace / 'docs/next/evidence/x55'
profile = f'x55-system-{os.getpid()}'
phase = sys.argv[1] if len(sys.argv) > 1 else 'all'
assert phase in ('all', 'system', 'verify', 'bandwidth')
root = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
assert not root.exists()
root.mkdir(parents=True, mode=0o700)
media = root / 'media'
media.mkdir()
harness = root / 'harness'
shutil.copytree(workspace / 'assets/next/harness', harness)
(harness / 'nipa').chmod(0o755)
(harness / 'records').mkdir()
home = root / 'codex-home'
home.mkdir(mode=0o700)
(home / 'config.toml').write_text('model = "unused-fixture"\n')
shutil.copy2('/etc/ssl/cert.pem', root / 'system-ca.pem')
# ChatHost's login-environment request is served locally; app-server is disabled.
# No shell startup file or user Codex configuration is consulted.
shell = root / 'fixture-shell'
shell.write_text('#!/usr/bin/python3\nimport os,sys\n'
                 'if "exec /usr/bin/env -0" in sys.argv:\n'
                 ' os.write(1, b"\\0".join((k+"="+v).encode() for k,v in os.environ.items())+b"\\0")\n'
                 ' sys.exit(0)\nsys.exit(78)\n')
shell.chmod(0o755)
hook = harness / 'hooks/settings.changed'
hook.write_text('#!/usr/bin/python3\nimport json,sys\nfrom pathlib import Path\n'
                'event=json.load(sys.stdin)\n'
                'Path("records/settings-event.json").write_text(json.dumps(event,ensure_ascii=False))\n'
                'print("Observed settings.changed for",event["entityId"])\n')
hook.chmod(0o755)
(root / 'preferences.json').write_text(json.dumps({
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
    'flutter.auto_check_updates_in_background': False,
    'flutter.next_startup_scan_enabled': False,
    'flutter.next_sidecar_index_enabled': False,
    'flutter.next_subtitle_probe_enabled': False,
}))
env = dict(os.environ, NIPAPLAY_PROFILE=profile, CODEX_HOME=str(home),
           SHELL=str(shell), CODEX_CA_CERTIFICATE=str(root / 'system-ca.pem'),
           SSL_CERT_FILE=str(root / 'system-ca.pem'),
           NO_PROXY='127.0.0.1,localhost,::1', no_proxy='127.0.0.1,localhost,::1')
for key in ('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy',
            'https_proxy', 'all_proxy', 'NIPAPLAY_LAB_QUIET'):
    env.pop(key, None)
executable = workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay'
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
records = []
secret = None
app = stream = endpoint = None


def clean(value):
    if isinstance(value, str):
        return value.replace(secret, '[REDACTED]') if secret else value
    if isinstance(value, list): return [clean(v) for v in value]
    if isinstance(value, dict): return {k: clean(v) for k, v in value.items()}
    return value


def record(label, value):
    records.append({'label': label, 'value': clean(value)})
    (evidence / f'operations-{phase}.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, flush=True)
    return value


def call(action, inputs=None, save=True):
    request = urllib.request.Request(endpoint['url'], data=json.dumps({
        'operation': 'call', 'action': action, 'input': inputs or {}}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + secret})
    with opener.open(request, timeout=90) as response: value = json.load(response)
    if save: record(action, {'input': inputs or {}, **value})
    if value['status'] != 'completed':
        raise RuntimeError(json.dumps(clean(value), ensure_ascii=False))
    return value['result']


def get_job(job_id):
    return call('task.get', {'jobId': job_id}, save=False)['job']


def wait_job(job_id):
    deadline = time.monotonic() + 240
    job = get_job(job_id)
    while time.monotonic() < deadline:
        if job['state'] in ('succeeded', 'failed', 'cancelled'):
            return record('job-terminal', job)
        job = call('task.wait', {'jobId': job_id, 'afterRevision': job['revision'],
                   'timeoutMs': 10000}, save=False)['job']
    raise TimeoutError('Owned task did not finish')


def cache_experiment():
    images = root / 'data/compressed_images'
    images.mkdir(parents=True, exist_ok=True)
    (images / 'x55-recoverable.jpg').write_bytes(b'X55 recoverable cache fixture\n' * 65536)
    before = call('storage.status')
    plan = call('cache.plan', {'kinds': ['images']})
    reclaimed = call('cache.prune', {'planId': plan['planId']})
    after = call('storage.status')
    def image_bytes(status):
        return next(d['bytes'] for d in status['directories'] if d['role'] == 'images')
    record('cache-comparison', {'beforeBytes': image_bytes(before), 'afterBytes': image_bytes(after),
           'removedBytes': reclaimed['removedBytes'], 'volumeBefore': before['volumes'],
           'volumeAfter': after['volumes']})
    assert image_bytes(before) - image_bytes(after) == reclaimed['removedBytes'] > 0
    watch = call('storage.watch', {'thresholdBytes': 0, 'intervalMs': 1000})['watch']
    call('storage.unwatch', {'watchId': watch['watchId']})
    return reclaimed


def notification_experiment():
    call('notification.status')
    notification = call('notification.send', {'id': profile, 'title': 'NipaPlay 实验通知',
                        'body': '后台能力验证已完成。', 'sound': False, 'requestPermission': False})
    time.sleep(1)
    call('notification.list')
    call('notification.cancel', {'id': profile})
    return notification


try:
    seed = media / 'seed.mp4'
    subprocess.run(['/opt/homebrew/bin/ffmpeg', '-hide_banner', '-loglevel', 'error',
                    '-f', 'lavfi', '-i', 'testsrc2=s=320x180:r=10', '-t', '2',
                    '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
                    str(seed)], check=True)
    content = seed.read_bytes()
    for i in range(192):
        # MP4 permits trailing data. Each owned fixture has distinct bytes.
        (media / f'fixture-{i:03}.mp4').write_bytes(content + f'X55 fixture {i}'.encode())
    record('fixture', {'license': 'CC0, generated testsrc2 and owned trailing text',
           'files': 193, 'bytes': sum(p.stat().st_size for p in media.iterdir())})
    stream = (root / 'application.log').open('w')
    app = subprocess.Popen([str(executable)], cwd=workspace, env=env,
                           stdout=stream, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        assert app.poll() is None, 'Owned executable exited'
        file = root / 'endpoint.json'
        if file.exists():
            endpoint = json.loads(file.read_text())
            secret = endpoint['token']
            try:
                instance = call('app.instance', save=False)
                break
            except (OSError, RuntimeError): pass
        time.sleep(.3)
    else: raise TimeoutError('Owned endpoint did not start')
    record('instance', {'profile': profile, 'pid': app.pid,
           'executable': str(executable), 'facts': instance, 'quiet': True,
           'modelHost': 'disabled by isolated fixture shell'})
    if phase == 'bandwidth':
        call('window.bounds.get')
        initial = call('download.limits.get')
        assert initial['supported'] and not initial['sessionInitialized']
        call('settings.set', {'key': 'download.directory', 'value': str(root / 'downloads')})
        call('settings.set', {'key': 'download.enabled', 'value': True})
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            current = call('download.limits.get', save=False)
            if current.get('sessionInitialized'): break
            time.sleep(.3)
        else: raise TimeoutError('Owned download session did not initialize')
        record('initialized-limits', current)
        applied = call('download.limits.set', {'downloadBytesPerSecond': 131072,
                                             'uploadBytesPerSecond': 65536})
        assert applied['applied'] and applied['actual'] == {
            'downloadBytesPerSecond': 131072, 'uploadBytesPerSecond': 65536}
        assert call('download.limits.get')['actual'] == applied['actual']
        preserved = call('download.limits.set', {'uploadBytesPerSecond': 0})
        assert preserved['actual'] == {'downloadBytesPerSecond': 131072, 'uploadBytesPerSecond': 0}
        reset = call('download.limits.set', {'downloadBytesPerSecond': 0, 'uploadBytesPerSecond': 0})
        assert reset['actual'] == {'downloadBytesPerSecond': 0, 'uploadBytesPerSecond': 0}
        record('verified', {'bandwidth': 'native session readback', 'throughputMeasured': False})
        raise SystemExit(0)
    if phase == 'verify':
        small = root / 'classic-media'
        small.mkdir()
        shutil.copy2(seed, small / 'test.mp4')
        call('media.library.roots.add', {'paths': [str(small)]})
        classic = call('media.library.scan_classic', {'paths': [str(small)]})
        classic_terminal = wait_job(classic['jobId'])
        assert classic_terminal['state'] == 'succeeded'
        cache_experiment()
        call('network.status')
        notification_experiment()
        record('verified', {'classicScan': classic_terminal['state'], 'quiet': True})
        raise SystemExit(0)
    call('media.library.roots.add', {'paths': [str(media)]})
    call('task.resources')
    call('media.indexers.status')
    terminal = {'state': 'already_verified_in_initial_run'}
    scan = call('media.library.scan', {'root': str(media), 'requestId': profile})['job'] if phase == 'all' else None
    deadline = time.monotonic() + 60
    while scan and time.monotonic() < deadline:
        current = get_job(scan['jobId'])
        if current['progress']['completed'] >= 3 and current['state'] == 'running': break
        time.sleep(.05)
    if scan:
        if current['state'] != 'running': raise TimeoutError('No running scan progress observed')
        record('scan-before-pause', current)
        paused = call('task.control', {'entries': [{'jobId': scan['jobId'], 'command': 'pause'}]})
        assert paused['results'][0]['accepted']
        time.sleep(1.5)
        first = get_job(scan['jobId'])
        time.sleep(1.5)
        second = get_job(scan['jobId'])
        record('scan-paused-stable', {'first': first, 'second': second,
               'equalProgress': first['progress'] == second['progress']})
        assert first['state'] == second['state'] == 'paused'
        assert first['progress'] == second['progress']
        resumed = call('task.control', {'entries': [{'jobId': scan['jobId'], 'command': 'resume'}]})
        assert resumed['results'][0]['accepted']
        terminal = wait_job(scan['jobId'])
        assert terminal['state'] == 'succeeded'
        assert terminal['receipt']['details']['indexed'] == 193
    # Register a followup while the model host is absent; retain trigger facts.
    followup = call('followup.register', {'when': {'event': 'settings.changed',
        'objectId': 'network.mediaServerUserAgent'}, 'threadId': 'x55-unavailable-fixture-thread',
        'title': 'X55 设置事实', 'instruction': '记录设置变化的事实。'})['followup']
    cursor = call('events.wait', {'timeoutMs': 0, 'limit': 1000})['nextCursor']
    call('settings.set', {'key': 'network.mediaServerUserAgent', 'value': 'NipaPlay-X55-Fixture/1.0'})
    events = call('events.wait', {'afterCursor': cursor, 'events': ['settings.changed'],
                  'entityId': 'network.mediaServerUserAgent', 'timeoutMs': 10000})
    assert events['events']
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        jobs = call('task.list', {'type': 'harness.hook'}, save=False)['jobs']
        match = [j for j in jobs if j.get('objectId') == 'network.mediaServerUserAgent'
                 and j['state'] == 'succeeded']
        if match: break
        time.sleep(.2)
    else: raise TimeoutError('settings hook did not complete')
    record('hook-receipt', match[-1])
    record('hook-file', json.loads((harness / 'records/settings-event.json').read_text()))
    time.sleep(1)
    call('followup.list')
    call('followup.cancel', {'id': followup['id']})
    reclaimed = cache_experiment()
    call('app.update.check')
    call('app.update.status')
    call('diagnostics.status')
    call('diagnostics.file_logs', {'limit': 10})
    call('network.status')
    notification = notification_experiment()
    record('completed', {'scan': terminal['state'], 'hook': 'succeeded',
           'cacheRemovedBytes': reclaimed['removedBytes'], 'notification': notification})
except Exception as error:
    record('experiment-failed', {'type': type(error).__name__, 'message': str(error)})
    raise
finally:
    owned_pid = app.pid if app else None
    if app is not None and app.poll() is None:
        app.terminate()
        try: app.wait(timeout=25)
        except subprocess.TimeoutExpired:
            app.kill()
            app.wait(timeout=10)
    if stream: stream.close()
    shutil.rmtree(root)
    record('cleanup', {'pid': owned_pid, 'exitCode': app.returncode if app else None,
           'profileRemoved': not root.exists(), 'otherInstancesTouched': False})
