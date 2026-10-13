"""Observe the final public CLI facts and host-only credential enrollment."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

workspace = Path(__file__).resolve().parents[2]
root = Path(tempfile.mkdtemp(prefix='x53-facts-', dir='/tmp/nipa-next'))
data = root / 'body'
output = workspace / 'docs/next/evidence/x53/final-facts.json'
env = {k: v for k, v in os.environ.items() if k.lower() not in {'http_proxy', 'https_proxy', 'all_proxy'}}
env.update(NO_PROXY='127.0.0.1,localhost', NIPAPLAY_PROFILE='x53-facts',
    NIPAPLAY_ENDPOINT_FILE=str(data / 'endpoint.json'))
log = (root / 'node.log').open('w')
child = subprocess.Popen([workspace / 'build/headless/nipaplay-headless', '--data', data],
    cwd=workspace, env=env, stdout=log, stderr=subprocess.STDOUT)
records = []

def record(label, value):
    records.append({'label': label, 'value': value})
    output.write_text(json.dumps(records, ensure_ascii=False, indent=2))

def nipa(*args):
    result = subprocess.run(['python3', str(workspace / 'assets/next/harness/nipa'), *args],
        cwd=workspace, env=env, capture_output=True, text=True, check=True)
    return json.loads(result.stdout)

try:
    deadline = time.monotonic() + 45
    while not (data / 'endpoint.json').exists():
        assert child.poll() is None
        assert time.monotonic() < deadline
        time.sleep(.2)
    catalog = nipa('list', '--full')['actions']
    flags = {a['id']: a for a in catalog}
    assert flags['media.hash.match']['available'] is False
    assert flags['program.run']['available'] is False
    assert flags['danmaku.align']['lifecycle'] == 'legacyRecovery'
    assert all(a['remoteCallable'] for a in catalog)
    record('missing-prerequisites-explicit', [flags[k] for k in [
        'media.hash.match', 'program.run', 'danmaku.align']])
    record('app-family', nipa('describe', 'app'))
    record('danmaku-family', nipa('describe', 'danmaku'))
    marker = root / 'invalid-host'
    marker.mkdir()
    (marker / 'headless.json').write_text('{"format":1,"host":"other"}')
    invalid = subprocess.run([workspace / 'build/headless/nipaplay-headless', '--data', marker,
        '--enroll-credential-stdin', '--credential-namespace', 'metadata', '--credential-key', 'tmdb'],
        input=b'synthetic-credential', env=env, capture_output=True)
    assert invalid.returncode != 0 and not (marker / 'vault').exists()
    record('unrecognized-host-enrollment-refused', {'refused': True, 'vaultWritten': False})
    subprocess.run([workspace / 'build/headless/nipaplay-headless', '--data', data,
        '--enroll-credential-stdin', '--credential-namespace', 'metadata', '--credential-key', 'tmdb'],
        input=b'synthetic-credential', env=env, capture_output=True, check=True)
    facts = nipa('call', 'app.capabilities', '{}')['result']
    tmdb = next(p for p in facts['providers'] if p['id'] == 'tmdb')
    assert tmdb['available'] and tmdb['credentialRef'] == {'namespace': 'metadata', 'key': 'tmdb'}
    assert 'synthetic-credential' not in json.dumps(facts)
    record('live-host-vault-readiness', facts)
finally:
    if child.poll() is None:
        child.terminate()
        try:
            child.wait(timeout=30)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
    log.close()
    shutil.rmtree(root)
    record('cleanup', {'pid': child.pid, 'removed': not root.exists(), 'exited': child.poll() is not None})
