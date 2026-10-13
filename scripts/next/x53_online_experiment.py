"""Owned quiet GUI/headless comparison on the CC BY Blender film Big Buck Bunny.

Only the supplied disposable Dandanplay test account is read. No real media
server accounts, system keychain, application activation or workstation node.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import urllib.request
import zipfile

workspace = Path(__file__).resolve().parents[2]
root = Path('/tmp/nipa-next/x53-online')
assert root.is_dir()
profile = 'x53-online-' + str(os.getpid())
gui = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
assert not gui.exists()
gui.mkdir(parents=True)
source_check = os.environ.get('X53_PHASE') == 'source-check'
completion = source_check or os.environ.get('X53_PHASE') == 'headless-completion'
preparation = completion or os.environ.get('X53_PHASE') == 'preparation'
evidence = workspace / ('docs/next/evidence/x53/source-check.json' if source_check else
    'docs/next/evidence/x53/completion.json' if completion else
    'docs/next/evidence/x53/preparation.json' if preparation else 'docs/next/evidence/x53/online.json')
env = {k: v for k, v in os.environ.items() if k.lower() not in {'http_proxy', 'https_proxy', 'all_proxy'}}
env['NO_PROXY'] = '127.0.0.1,localhost'
headless_env = dict(env, **{k: v for k, v in os.environ.items()
    if k.lower() in {'http_proxy', 'https_proxy', 'all_proxy'}})
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
children, logs, records = [], [], []

def record(label, value):
    records.append({'label': label, 'value': value})
    evidence.write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, flush=True)

def wait(predicate, seconds=90):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        result = predicate()
        if result:
            return result
        if any(child.poll() is not None for child in children):
            raise RuntimeError('owned instance exited; inspect temporary redacted log')
        time.sleep(.25)
    raise RuntimeError('observation deadline')

def request(data, operation, **fields):
    endpoint = json.loads((data / 'endpoint.json').read_text())
    url = endpoint['url'].replace('/mcp', '/harness')
    req = urllib.request.Request(url, data=json.dumps({'operation': operation, **fields}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + endpoint['token']})
    with opener.open(req, timeout=55) as response:
        return json.load(response)

def call(data, action, inputs):
    result = request(data, 'call', action=action, input=inputs)
    if result['status'] != 'completed':
        record(action + '-failure', result)
        raise RuntimeError('action did not complete: ' + action)
    return result['result']

def task(data, job_id):
    result = wait(lambda: terminal(data, job_id), 90)
    if result['state'] != 'succeeded':
        record('task-failure', result)
        raise RuntimeError('task did not succeed')
    return result

def terminal(data, job_id):
    job = call(data, 'task.get', {'jobId': job_id})['job']
    return job if job['state'] in {'succeeded', 'failed', 'cancelled'} else None

def spawn(command, data, environment):
    log = (root / (data.name + '.log')).open('w')
    logs.append(log)
    child = subprocess.Popen([str(x) for x in command], cwd=workspace, env=environment,
        stdout=log, stderr=subprocess.STDOUT)
    children.append(child)
    wait(lambda: (data / 'endpoint.json').exists())

try:
    if not any((root / 'media').rglob('*.mp4')):
        with zipfile.ZipFile(root / 'bbb.zip') as archive:
            archive.extractall(root / 'media')
    video = next((root / 'media').rglob('*.mp4'))
    record('licensed-input', {'title': 'Big Buck Bunny', 'license': 'CC BY 3.0',
        'attribution': 'Blender Foundation / www.bigbuckbunny.org',
        'source': 'https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_320x180.mp4.zip',
        'bytes': video.stat().st_size, 'sha256': hashlib.file_digest(video.open('rb'), 'sha256').hexdigest()})
    (gui / 'preferences.json').write_text(json.dumps({
        'flutter.labs_enable_agent_endpoint': True,
        'flutter.labs_use_next_interface': False,
        'flutter.next_harness_path': str(gui / 'harness'),
        'flutter.auto_sync_enabled': False,
        'flutter.downloader_enabled': False,
        'flutter.dandanplay_server_mode': 'hongkong',
    }))
    spawn([workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay'],
        gui, dict(env, NIPAPLAY_PROFILE=profile))
    record('gui-instance', call(gui, 'app.instance', {}))
    # The existing GUI account service handles gateway login and host enrollment.
    account = json.loads(Path('/tmp/nipa-next/testservers.json').read_text())['dandanplay']
    job = call(gui, 'accounts.login', {'provider': 'dandanplay',
        'username': account['username'], 'password': account['password']})
    account = None
    login = task(gui, job['jobId'])
    record('test-account-enrollment', {'state': login['state'], 'secretsRecorded': False})
    token = json.loads((gui / 'credential-vault.json').read_text())['11:preferencesdandanplay_token']
    body = root / 'body'
    body.mkdir()
    (body / 'headless.json').write_text(json.dumps({'format': 1, 'host': 'nipaplay-headless'}))
    (body / 'network.json').write_text(json.dumps({'dandanplay_server_mode': 'hongkong'}))
    subprocess.run([str(workspace / 'build/headless/nipaplay-headless'), '--data', str(body), '--enroll-token-stdin'],
        input=token.encode(), env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, check=True)
    token = None
    spawn([workspace / 'build/headless/nipaplay-headless', '--data', body, '--media-root', root / 'media',
        '--ffprobe', '/opt/homebrew/bin/ffprobe'], body, dict(headless_env, NIPAPLAY_PROFILE=profile + '-headless'))
    record('headless-instance', call(body, 'app.instance', {}))
    if not completion:
        call(gui, 'media.library.roots.add', {'paths': [str(root / 'media')]})
    hosts = {'headless': body} if completion else {'gui': gui, 'headless': body}
    prepared = {}
    if source_check:
        record('headless-capabilities', call(body, 'app.capabilities', {}))
        matched = call(body, 'media.hash.match', {'files': [{'path': str(video)}]})
        assert matched['files'][0].get('candidates') == []
        record('headless-online-hash', matched)
        searched = call(body, 'media.metadata.search_batch', {'queries': [
            {'provider': 'dandanplay', 'query': 'Big Buck Bunny'},
            {'provider': 'bangumi', 'query': 'Big Buck Bunny'}]})
        assert all('error' not in entry for entry in searched['results'])
        record('headless-online-metadata-search', searched)
        record('headless-online-danmaku-search', request(body, 'call', action='danmaku.search',
            input={'sourceId': 'dandanplay', 'query': '大雄兔'}))
        raise SystemExit(0)
    if preparation:
        duration = int(float(subprocess.check_output(['/opt/homebrew/bin/ffprobe',
            '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=nw=1:nk=1', str(video)])) * 1000)
        ref = {'provider': 'bangumi', 'objectType': 'subject', 'externalId': '49696', 'scope': ''}
        pool = root / 'media/cc0-danmaku.json'
        pool.write_text(json.dumps([{'sourceTimeMs': 5000, 'text': 'Big Buck Bunny — Blender Foundation',
            'mode': 1, 'colorRgb': 16777215}, {'sourceTimeMs': 9000, 'text': 'CC BY 3.0 open movie',
            'mode': 1, 'colorRgb': 16777215}]))
        comparisons = {}
        if completion:
            prior = {row['label']: row['value'] for row in json.loads(
                (workspace / 'docs/next/evidence/x53/preparation.json').read_text())}
            movie = prior['gui-details']['results'][0]['record']
            comparisons['gui'] = {'work': movie['ref'], 'episode': movie['episodes'][0]['ref'],
                'title': movie['title'], 'overview': movie['overview'], 'durationMs': duration,
                'importCount': prior['gui-prepared-danmaku']['entries'][0]['result']['count']}
        for name, data in hosts.items():
            details = call(data, 'media.metadata.get_batch', {'refs': [ref]})
            record(name + '-details', details)
            movie = details['results'][0]['record']
            assert movie['originalTitle'] == 'Big Buck BUNNY' and movie['episodes']
            episode = movie['episodes'][0]
            bound = call(data, 'media.identity.bind_batch', {'requestId': 'x53-bbb-identity',
                'entries': [{'kind': 'file', 'path': str(video), 'workRef': ref,
                    'episodeRefs': [episode['ref']], 'reason': 'Explicitly selected the Blender film and its main episode; no hash candidate.',
                    'evidence': [{'source': 'https://download.blender.org/peach/bigbuckbunny_movies/',
                        'detail': 'Official full film, title/year/Blender attribution verified.'}]}]})
            record(name + '-persisted-identity', bound)
            file_id = bound['entries'][0]['fileId']
            online = request(data, 'call', action='danmaku.search', input={'sourceId': 'dandanplay', 'query': '大雄兔'})
            record(name + '-online-danmaku-search', online)
            imported = call(data, 'danmaku.import_batch', {'entries': [{'filePath': str(pool),
                'platform': 'cc0-x53', 'platformVideoId': 'big-buck-bunny', 'entityId': file_id,
                'note': 'Experimenter-authored CC0 fixture comments; not an online Dandanplay pool.'}]})
            record(name + '-prepared-danmaku', imported)
            tracks = call(data, 'danmaku.tracks', {'entityId': file_id})
            record(name + '-saved-tracks', tracks)
            identity = call(data, 'media.identity.get', {'entityId': file_id})
            record(name + '-saved-metadata', identity)
            comparisons[name] = {'work': movie['ref'], 'episode': episode['ref'],
                'title': movie['title'], 'overview': movie['overview'], 'durationMs': duration,
                'importCount': imported['entries'][0]['result']['count']}
        record('preparation-comparison', {'equal': comparisons['gui'] == comparisons['headless'],
            'observed': comparisons, 'onlinePoolClaimed': False})
        raise SystemExit(0)
    for name, data in hosts.items():
        facts = call(data, 'app.capabilities', {})
        record(name + '-capabilities', facts)
        record(name + '-family', request(data, 'describe', action='app'))
        record(name + '-hash', call(data, 'media.hash.match', {'files': [{'path': str(video)}]}))
        search = call(data, 'media.metadata.search_batch', {'queries': [
            {'provider': 'dandanplay', 'query': 'Big Buck Bunny'},
            {'provider': 'bangumi', 'query': 'Big Buck Bunny'}]})
        record(name + '-search', search)
        prepared[name] = search
    record('search-comparison', {'equal': prepared['gui'] == prepared['headless'],
        'note': 'fetchedAt may differ; inspect titles/refs before binding'})
except Exception as error:
    record('observation-stopped', {'type': type(error).__name__, 'reason': str(error)})
    raise
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
    shutil.rmtree(gui)
    # Preserve only the openly licensed input until this comparison is complete.
    for path in [root / 'body']:
        if path.exists():
            shutil.rmtree(path)
    record('owned-instances-removed', {'pids': [p.pid for p in children],
        'guiProfileRemoved': not gui.exists(), 'headlessDataRemoved': not (root / 'body').exists()})
