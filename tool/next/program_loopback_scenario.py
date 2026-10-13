"""X46 observations in the local headless fixture; no model or external nodes."""
import json
import os
from pathlib import Path
import subprocess
import time


def check_subscriptions(*, root, a, b, aid, bid, raw, invoke, call, wait, record):
    tools = raw('tools/list', {})['tools']
    subscription = next(t for t in tools if t['_meta']['nipaplay/actionId'] == 'followup.register')
    job = invoke(a, bid, 'program.run', {'title': 'manual return fixture',
        'command': 'sleep 2; echo subscribed', 'followup': False})
    ticket = 'synthetic-manual-return-target'
    target = {'threadId': 'original-manual-thread', 'repository': str(a/'harness'),
              'origin': 'harness_cli:chat:synthetic', 'invocationId': 'fixture-subscription'}
    (a/'mesh-return-targets.json').write_text(json.dumps({ticket: {'peer': bid, **target}}))
    subscribed = raw('tools/call', {'name': subscription['name'], 'arguments': {
        'instruction': 'custom fixture followup', 'when': {'jobId': job['jobId']}},
        'returnTo': {**target, 'deviceId': aid, 'returnTicket': ticket}})['structuredContent']
    assert subscribed['status'] == 'completed', subscribed
    row = wait(lambda: next((r for r in call(a, 'followup.list', {})['followups']
                              if r.get('automatic') == 'meshSubscription'), None))
    assert row['threadId'] == target['threadId'] and row['sourceDeviceId'] == bid
    assert row['instruction'] == 'custom fixture followup'
    assert row['trigger']['receipt']['details']['stdoutTail'].strip() == 'subscribed'
    assert all(r.get('automatic') != 'meshProgram' for r in call(a, 'followup.list', {})['followups'])
    record('manual-remote-subscription-original-thread', {'submitted': subscribed,
        'destination': row, 'source': call(b, 'followup.list', {}),
        'job': invoke(a, bid, 'task.get', {'jobId': job['jobId']}),
        'modelTurns': 0, 'workstationConnections': 0})


def check_programs(*, root, a, b, aid, bid, raw, invoke, call, wait, record, env, workspace):
    tools = raw('tools/list', {})['tools']
    catalog = {t['_meta']['nipaplay/actionId']: t for t in tools}
    required = {'program.run', 'program.repository.receive', 'subtitle.import',
                'subtitle.tracks', 'subtitle.select', 'settings.describe', 'followup.register'}
    assert required <= catalog.keys()
    assert 'settings.set' not in catalog and 'accounts.login' not in catalog
    record('remote-scope', {'present': sorted(required), 'hostMutationAbsent': True,
                           'settings': invoke(a, bid, 'settings.describe', {'limit': 2})})
    # A keeps its absent/default-off permission. The same-account peer is denied.
    cli = workspace / 'assets/next/harness/nipa'
    def nipa(data, device, *arguments, success=True):
        result = subprocess.run(['python3', cli, '--device', device, *arguments],
            cwd=data/'harness', env=dict(env, NIPAPLAY_ENDPOINT_FILE=str(data/'endpoint.json')),
            capture_output=True, text=True, timeout=65)
        value = json.loads(result.stdout)
        assert (result.returncode == 0) == success, value
        return value
    denied = nipa(b, aid, 'call', 'program.run', json.dumps({'title': 'off', 'command': 'echo forbidden'}), success=False)
    assert denied['status'] == 'failed'
    record('default-off-denial', denied)

    source = root/'source-repository'
    source.mkdir()
    script = '''import os, pathlib, subprocess, json
assert "CODEX_HOME" not in os.environ and "OPENAI_API_KEY" not in os.environ
assert "HTTP_PROXY" not in os.environ and "NIPAPLAY_CHAT" not in os.environ
print(json.dumps({"cwd":os.getcwd(), "isolatedEnvironment":True,
                  "targetEndpoint":bool(os.environ.get("NIPAPLAY_ENDPOINT_FILE"))}))
subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=64x64",
                "-frames:v", "1", "records/frame.jpg"], check=True)
print("token=" + "synthetic-output-fixture")
print("program complete")
'''
    (source/'probe.py').write_text(script)
    # Large committed object forces multiple mesh frames; no private data.
    (source/'fixture.bin').write_bytes(os.urandom(900000))
    def git(*arguments):
        subprocess.run(['git', '-C', source, *arguments], check=True, capture_output=True, env=env)
    git('init', '-b', 'main')
    git('add', 'probe.py', 'fixture.bin')
    git('-c', 'user.name=Local fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'fixture')
    # These files and local remote configuration never belong to the bundle.
    (source/'untracked-private').write_text('not transferred')
    (source/'.git/config').write_text((source/'.git/config').read_text() + '\n[fixture]\n\tprivate = not-transferred\n')
    synced = nipa(a, bid, 'sync-repository', '--repository', str(source))
    bundle = synced['bundle']['path']
    assert synced['bundle']['complete'] and Path(bundle).stat().st_size > 393216
    clone_command = "git -c core.hooksPath=/dev/null clone '{}' records/synced".format(bundle)
    def run(command, title='Local program observation', **options):
        return invoke(a, bid, 'program.run', {'title': title, 'command': command, **options})['jobId']
    def terminal(jid):
        return wait(lambda: (j if j['state'] in {'succeeded', 'failed', 'cancelled'} else None)
                    if (j := invoke(a, bid, 'task.get', {'jobId': jid})['job']) else None)
    cloned = terminal(run(clone_command))
    assert cloned['state'] == 'succeeded', cloned
    destination = b/'harness/records/synced'
    assert (destination/'probe.py').read_text() == script
    assert not (destination/'untracked-private').exists()
    assert 'not-transferred' not in (destination/'.git/config').read_text()
    record('git-bundle-transfer', {'revision': synced['revision'], 'bundle': synced['bundle'],
        'clone': cloned, 'untrackedAndConfigAbsent': True})

    ticket = 'synthetic-issued-program-target'
    target = {'threadId': 'original-synthetic-thread', 'repository': str(a/'harness'),
              'origin': 'harness_cli:chat:synthetic', 'invocationId': 'fixture-program'}
    (a/'mesh-return-targets.json').write_text(json.dumps({ticket: {'peer': bid, **target}}))
    submitted = raw('tools/call', {'name': catalog['program.run']['name'],
        'arguments': {'title': '远端 ffmpeg 抽帧夹具', 'command': 'python3 records/synced/probe.py'},
        'returnTo': {**target, 'deviceId': aid, 'returnTicket': ticket}})['structuredContent']
    assert submitted['status'] == 'completed', submitted
    jid = submitted['result']['jobId']
    completed = terminal(jid)
    assert completed['state'] == 'succeeded', completed
    output = completed['receipt']['details']['stdoutTail']
    assert 'synthetic-output-fixture' not in output and 'program complete' in output
    assert 'isolatedEnvironment' in output and '"targetEndpoint": true' in output
    assert (b/'harness/records/frame.jpg').stat().st_size > 0
    def returned():
        return next((r for r in call(a, 'followup.list', {})['followups']
                     if r.get('automatic') == 'meshProgram'), None)
    delivery = wait(returned)
    assert delivery['threadId'] == target['threadId'] and delivery['sourceDeviceId'] == bid
    assert delivery['trigger']['facts'][0]['data']['receipt']['details']['exitCode'] == 0
    activity = invoke(a, bid, 'state.query', {'view': 'activity', 'limit': 100})
    assert jid in json.dumps(activity) and 'python3 records/synced/probe.py' in json.dumps(activity)
    assert 'synthetic-output-fixture' not in (b/'journal.jsonl').read_text()
    record('program-receipt-and-original-thread', {'job': completed, 'destination': delivery,
        'source': call(b, 'followup.list', {}), 'activity': activity,
        'frameBytes': (b/'harness/records/frame.jpg').stat().st_size, 'modelTurns': 0})

    child = b/'harness/records/child.py'
    child.write_text('import subprocess,sys,pathlib\np=subprocess.Popen([sys.executable,"-c","import time;time.sleep(120)"])\npathlib.Path("records/child.pid").write_text(str(p.pid))\np.wait()\n')
    cancel_id = run('python3 records/child.py', 'cancel fixture')
    child_pid = int(wait(lambda: (b/'harness/records/child.pid').read_text()
                         if (b/'harness/records/child.pid').exists() else None))
    invoke(a, bid, 'task.cancel', {'jobId': cancel_id})
    cancelled = terminal(cancel_id)
    assert cancelled['state'] == 'cancelled', cancelled
    ps = subprocess.run(['/bin/ps', '-p', str(child_pid), '-o', 'stat='], capture_output=True, text=True)
    assert ps.returncode != 0 or ps.stdout.strip().startswith('Z'), ps.stdout
    timed = terminal(run('python3 -c "import time; time.sleep(120)"', 'timeout fixture', timeoutSeconds=1))
    assert timed['state'] == 'failed' and timed['receipt']['details']['timedOut']
    nonzero = terminal(run('exit 7', 'nonzero fixture'))
    assert nonzero['state'] == 'failed' and nonzero['receipt']['details']['exitCode'] == 7
    record('cancel-timeout-nonzero', {'cancelled': cancelled, 'childTerminated': True,
                                   'timeout': timed, 'nonzero': nonzero})

    # Remote subtitle actions operate on the source-node library, with no player.
    video = b/'downloads/Show01.mp4'
    video.write_bytes(b'local media fixture')
    sidecar = b/'downloads/Show01.en.srt'
    sidecar.write_text('1\n00:00:00,000 --> 00:00:01,000\nlocal subtitle\n')
    scan = invoke(a, bid, 'media.library.scan', {'root': str(b/'downloads'), 'requestId': 'x46-subtitles'})
    terminal(scan['job']['jobId'])
    files = invoke(a, bid, 'media.files.list', {'root': str(b/'downloads')})
    file_id = files['files'][0]['fileId']
    incoming = b/'harness/records/provided.srt'
    incoming.write_text('1\n00:00:00,000 --> 00:00:01,000\n字幕\n')
    imported = invoke(a, bid, 'subtitle.import', {'entries': [{'fileId': file_id,
        'filePath': str(incoming), 'language': 'zh-Hans', 'source': {'label': 'local fixture'}}]})
    track = imported['entries'][0]['track']
    selected = invoke(a, bid, 'subtitle.select', {'fileId': file_id, 'trackId': track['id']})
    incoming.unlink()
    assert Path(track['path']).exists() and selected['selection']['trackId'] == track['id']
    tracks = wait(lambda: (v if any(t['origin'] == 'sidecar' for t in v['files'][0]['tracks']) else None)
                  if (v := invoke(a, bid, 'subtitle.tracks', {'fileIds': [file_id]})) else None)
    record('headless-remote-subtitles', {'imported': imported, 'selected': selected, 'tracks': tracks,
                                      'originalDeletedSavedContentRetained': True})
    record('scope-and-isolation', {'network': 'loopback only', 'gateway': 'synthetic /UserId; default pointer',
           'meshBroadcast': False, 'modelTurns': 0, 'workstationConnections': 0, 'torrentDownloads': 0})
