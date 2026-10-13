"""Compare real host pipelines over a disposable NipaPlay-compatible loopback gateway.

The catalog/hash/comments are explicitly synthetic fixtures on licensed BBB bytes.
No public upstream signing client, real account, keychain or workstation node.
"""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.request

workspace = Path(__file__).resolve().parents[2]
root = Path(tempfile.mkdtemp(prefix='x53-gateway-', dir='/tmp/nipa-next'))
profile = 'x53-gateway-' + str(os.getpid())
gui = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
assert not gui.exists()
gui.mkdir()
evidence = workspace / 'docs/next/evidence/x53/gateway.json'
token = secrets.token_urlsafe(32)
records, trace, children, logs = [], [], [], []
env = {k: v for k, v in os.environ.items() if k.lower() not in {'http_proxy', 'https_proxy', 'all_proxy'}}
env['NO_PROXY'] = '127.0.0.1,localhost'
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
catalog = {'animeId': 42, 'animeTitle': 'Big Buck Bunny (X53 synthetic catalog)',
    'summary': 'Licensed Blender film; fixture catalog, not a public Dandanplay identity.',
    'episodes': [{'episodeId': 4201, 'episodeTitle': 'Full film (fixture)', 'episodeNumber': '1'}]}

def record(label, value):
    records.append({'label': label, 'value': value})
    evidence.write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, flush=True)

class Gateway(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        route = self.path.split('?')[0]
        authorized = self.headers.get('Authorization') == 'Bearer ' + token
        trace.append({'method': self.command, 'path': route, 'expectedCredential': authorized})
        if not authorized:
            value, status = {'success': False}, 401
        elif route == '/dandanplay/api/v2/bangumi/42':
            value, status = {'success': True, 'bangumi': catalog}, 200
        elif route == '/dandanplay/api/v2/search/anime':
            value, status = {'success': True, 'animes': [catalog]}, 200
        elif route == '/dandanplay/api/v2/search/episodes':
            value, status = {'success': True, 'animes': [catalog]}, 200
        elif route == '/dandanplay/api/v2/comment/4201':
            value, status = {'success': True, 'comments': [
                {'cid': 1, 'p': '1,1,16777215,fixture', 'm': 'CC0 experimenter-authored fixture one'},
                {'cid': 2, 'p': '2,1,16777215,fixture', 'm': 'CC0 experimenter-authored fixture two'}]}, 200
        elif route == '/dandanplay/api/v2/match':
            value, status = {'success': True, 'isMatched': True, 'matches': [
                {'animeId': 42, 'animeTitle': catalog['animeTitle'],
                 'episodeId': 4201, 'episodeTitle': 'Full film (fixture)', 'episodeNumber': '1'}]}, 200
        else:
            value, status = {}, 404
        payload = json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', '0')))
        self.do_GET()

server = ThreadingHTTPServer(('127.0.0.1', 0), Gateway)
threading.Thread(target=server.serve_forever, daemon=True).start()
gateway = f'http://127.0.0.1:{server.server_port}/dandanplay'

def wait(predicate, seconds=60):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        result = predicate()
        if result:
            return result
        if any(p.poll() is not None for p in children):
            raise RuntimeError('owned node exited')
        time.sleep(.2)
    raise RuntimeError('observation deadline')

def call(data, action, inputs):
    endpoint = json.loads((data / 'endpoint.json').read_text())
    request = urllib.request.Request(endpoint['url'].replace('/mcp', '/harness'),
        data=json.dumps({'operation': 'call', 'action': action, 'input': inputs}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + endpoint['token']})
    with opener.open(request, timeout=50) as response:
        result = json.load(response)
    if result['status'] != 'completed':
        record('action-failure', {'action': action, 'outcome': result})
        raise RuntimeError('action did not complete: ' + action)
    return result['result']

def spawn(command, data, environment):
    log = (root / (data.name + '.log')).open('w')
    logs.append(log)
    child = subprocess.Popen([str(x) for x in command], cwd=workspace, env=environment,
        stdout=log, stderr=subprocess.STDOUT)
    children.append(child)
    wait(lambda: (data / 'endpoint.json').exists())

def terminal(data, job_id):
    job = call(data, 'task.get', {'jobId': job_id})['job']
    return job if job['state'] in {'succeeded', 'failed', 'cancelled'} else None

try:
    media = root / 'media'
    media.mkdir()
    video = media / 'BigBuckBunny.mp4'
    shutil.copyfile('/tmp/nipa-next/x53-online/media/BigBuckBunny_320x180.mp4', video)
    duration = int(float(subprocess.check_output(['/opt/homebrew/bin/ffprobe', '-v', 'error',
        '-show_entries', 'format=duration', '-of', 'default=nw=1:nk=1', str(video)])) * 1000)
    record('fixture-input', {'type': 'syntheticGateway', 'videoLicense': 'CC BY 3.0',
        'commentLicense': 'CC0', 'publicPoolClaimed': False, 'bytes': video.stat().st_size,
        'sha256': hashlib.file_digest(video.open('rb'), 'sha256').hexdigest()})
    ref = {'namespace': 'preferences', 'key': 'dandanplay_token'}
    vault = gui / 'credential-vault.json'
    vault.write_text(json.dumps({'11:preferencesdandanplay_token': token}))
    vault.chmod(0o600)
    (gui / 'preferences.json').write_text(json.dumps({
        'flutter.labs_enable_agent_endpoint': True, 'flutter.labs_use_next_interface': False,
        'flutter.next_harness_path': str(gui / 'harness'), 'flutter.downloader_enabled': False,
        'flutter.auto_sync_enabled': False, 'flutter.dandanplay_server_mode': 'custom',
        'flutter.dandanplay_server_url': gateway, 'flutter.dandanplay_logged_in': True,
        'flutter.dandanplay_token': json.dumps({'credentialRef': ref}),
        'flutter.last_token_renew_time': int(time.time() * 1000)}))
    body = root / 'body'
    body.mkdir()
    (body / 'headless.json').write_text(json.dumps({'format': 1, 'host': 'nipaplay-headless'}))
    (body / 'network.json').write_text(json.dumps({'dandanplay_server_mode': 'custom', 'dandanplay_server_url': gateway}))
    subprocess.run([workspace / 'build/headless/nipaplay-headless', '--data', body, '--enroll-token-stdin'],
        input=token.encode(), env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, check=True)
    spawn([workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay'],
        gui, dict(env, NIPAPLAY_PROFILE=profile))
    spawn([workspace / 'build/headless/nipaplay-headless', '--data', body, '--media-root', media,
        '--ffprobe', '/opt/homebrew/bin/ffprobe'], body, dict(env, NIPAPLAY_PROFILE=profile + '-headless'))
    call(gui, 'media.library.roots.add', {'paths': [str(media)]})
    observed = {}
    for name, data in [('gui', gui), ('headless', body)]:
        record(name + '-instance', call(data, 'app.instance', {}))
        matched = call(data, 'media.hash.match', {'files': [{'path': str(video)}]})
        record(name + '-hash-match', matched)
        signal = matched['files'][0]['candidates'][0]
        bound = call(data, 'media.identity.bind_batch', {'requestId': 'fixture-bbb', 'entries': [
            {'kind': 'file', 'path': str(video), 'workRef': signal['ref'],
             'episodeRefs': [signal['episodes'][0]['ref']],
             'reason': 'Explicit X53 synthetic catalog binding on licensed bytes.'}]})
        record(name + '-identity', bound)
        file_id = bound['entries'][0]['fileId']
        videos = call(data, 'danmaku.search', {'sourceId': 'dandanplay', 'query': 'Big Buck Bunny'})
        record(name + '-online-search', videos)
        platform_video = dict(videos['results'][0], durationMs=duration)
        attached = call(data, 'danmaku.attach_batch', {'entries': [{
            'video': platform_video, 'entityId': file_id, 'requestId': 'fixture-online-pool',
            'reason': 'Acquire experimenter-authored CC0 comments from the temporary gateway.'}]})
        record(name + '-attach', attached)
        row = attached['entries'][0]['result']
        job = wait(lambda: terminal(data, row['jobId']))
        record(name + '-fetch-receipt', job)
        assert job['state'] == 'succeeded'
        tracks = call(data, 'danmaku.tracks', {'entityId': file_id})
        record(name + '-tracks', tracks)
        identity = call(data, 'media.identity.get', {'entityId': file_id})
        record(name + '-metadata', identity)
        observed[name] = {'workRef': signal['ref'], 'episodeRef': signal['episodes'][0]['ref'],
            'jobState': job['state'], 'tracks': tracks}
    record('comparison', {'identityEqual': observed['gui']['workRef'] == observed['headless']['workRef'] and
        observed['gui']['episodeRef'] == observed['headless']['episodeRef'],
        'fetchSucceededBoth': all(v['jobState'] == 'succeeded' for v in observed.values()),
        'note': 'Different local file/binding/job IDs are expected; compare comments/count/coverage in track and task receipts.'})
    record('gateway-requests', trace)
finally:
    for child in reversed(children):
        if child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=30)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
    for log in logs:
        log.close()
    server.shutdown()
    server.server_close()
    shutil.rmtree(gui)
    shutil.rmtree(root)
    record('cleanup', {'pids': [p.pid for p in children], 'guiRemoved': not gui.exists(),
        'headlessRemoved': not root.exists(), 'gatewayStopped': True})
