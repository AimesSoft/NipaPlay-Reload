#!/usr/bin/env python3
"""Run inside player_core_f_lab.zsh; writes evidence without reading next.db."""
import json
import os
from pathlib import Path
import re
import signal
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

root = Path(sys.argv[1])
profile = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles/core-lab-f'
artifacts = profile / 'cache/player-core-f' / root.name
artifacts.mkdir(parents=True, exist_ok=True)
log = root / 'run.log'
url = re.findall(r'Dart VM service is listening on (http://[^\s]+)', log.read_text(errors='replace'))[-1]
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def rpc(method, **params):
    with opener.open(url + method + '?' + urllib.parse.urlencode(params), timeout=55) as response:
        result = json.load(response)
    if 'error' in result:
        raise RuntimeError(result['error'])
    return result['result']


isolate = next(i['id'] for i in rpc('getVM')['isolates'] if i['name'] == 'main')


def extension(name, **params):
    return rpc('ext.nipaplay.' + name, isolateId=isolate, **params)


receipts = []


def call(action, data=None):
    result = extension('nextui', op='guicall', action=action,
                       input=json.dumps(data or {}, ensure_ascii=False))
    receipts.append({'action': action, 'input': data or {}, 'response': result})
    (root / 'actions.json').write_text(json.dumps(receipts, ensure_ascii=False, indent=2))
    return result.get('result', result)


def shot(name):
    # The supported application-window capture route, never a desktop capture.
    proc = subprocess.run(['./nipa', 'call', 'ui.capture', '{}'],
                          cwd=profile / 'harness', capture_output=True, text=True, timeout=55)
    (root / (name + '-receipt.json')).write_text(proc.stdout + proc.stderr)
    data = json.loads(proc.stdout)
    def find(value):
        if isinstance(value, dict):
            if isinstance(value.get('path'), str) and value['path'].endswith('.png'):
                return value['path']
            for child in value.values():
                found = find(child)
                if found:
                    return found
        return None
    path = find(data)
    if path:
        shutil.copyfile(path, root / (name + '.png'))


def state():
    return call('playback.state')['state']


downloads = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles/e2e42b/data/downloads'
episode = next(p for p in downloads.rglob('*.mkv')
               if p.parts[-2].startswith('c8151aed'))
catalog = extension('player.features', op='catalog')
(root / 'catalog.json').write_text(json.dumps(catalog, indent=2))
settings = ['player.externalEnabled', 'player.externalPath', 'player.externalType',
            'player.timelinePreviewEnabled']
saved = {}
original_kernel = call('settings.get', {'key': 'player.kernel'}).get('value')


def setting(key, value):
    return call('settings.set', {'key': key, 'value': value, 'reason': 'F 线隔离实机验收'})


try:
    setting('player.kernel', 'mdk')
    saved = {key: call('settings.get', {'key': key}).get('value') for key in settings}
    setting('player.externalEnabled', False)
    setting('player.timelinePreviewEnabled', True)
    extension('player.perf', op='reset', frames='true')
    opened = call('playback.open', {'path': str(episode), 'startPositionMs': 10000})
    assert 'failure' not in opened, opened
    current = state()
    call('playback.wait', {'sessionId': current['sessionId'], 'until': 'playing', 'timeoutMs': 5000})
    call('playback.info')
    time.sleep(3)
    (root / 'perf-cold.json').write_text(json.dumps(extension('player.perf', op='read'), indent=2))
    extension('player.perf', op='reset', frames='true')
    current = state()
    call('playback.seek', {'positionMs': int(current['durationMs'] * .7)})
    time.sleep(2)
    call('playback.set_paused', {'paused': True})
    current = state()
    call('playback.capture', {'kind': 'screenshot', 'outputPath': str(artifacts / 'midpoint.png'),
                              'includeDanmaku': True})
    shot('midpoint-ui')
    chapter_result = call('playback.chapters')
    if chapter_result.get('items'):
        call('playback.navigate', {'sessionId': current['sessionId'], 'chapterIndex': min(1, len(chapter_result['items']) - 1)})
    call('playback.navigate', {'sessionId': current['sessionId'], 'frameDelta': 1})
    call('playback.navigate', {'sessionId': current['sessionId'], 'frameDelta': -1})
    gif = call('playback.capture', {'kind': 'gif', 'outputPath': str(artifacts / 'sample.gif'),
                              'startMs': 60000, 'endMs': 61000, 'fps': 6, 'width': 320, 'height': 180})
    assert gif.get('frames', 0) > 1 and gif.get('bytes', 0) > 0, gif
    assert (artifacts / 'sample.gif').read_bytes()[:6] in (b'GIF87a', b'GIF89a')
    preview = extension('player.features', op='preview', atMs='60000', outputPath=str(artifacts / 'preview.jpg'))
    (root / 'preview.json').write_text(json.dumps(preview, indent=2))
    remote = [extension('player.features', op='remote', command='toggle_play_pause'),
              extension('player.features', op='remote', command='seek_by_seconds',
                        args=json.dumps({'seconds': 11})),
              extension('player.features', op='remote', command='toggle_play_pause')]
    (root / 'remote.json').write_text(json.dumps(remote, ensure_ascii=False, indent=2))
    call('playback.levels', {'volume': 0})
    call('playback.retry', {'sessionId': current['sessionId'], 'preservePosition': True})
    call('playback.failures')
    call('playback.cancel_auto_next')
    call('playback.kernel', {'properties': ['position'], 'sampleMs': 500})
    for action, data in [
        ('playback.kernel_command', {'command': ['get_property', 'time-pos']}),
        ('playback.kernel_invoke', {'method': 'snapshot'}),
        ('playback.set_kernel_properties', {'properties': {'volume': 0}}),
        ('playback.restore_kernel_properties', {'names': ['volume']}),
        ('playback.reopen_with_kernel', {'kernel': 'mdk'}),
    ]:
        call(action, {'sessionId': state()['sessionId'], **data})
    call('playback.watch_kernel_properties', {'properties': ['position'], 'durationMs': 0})
    # Cross-track actions are called with valid inputs. Missing peer modules
    # remain visible in receipts rather than being disguised as successes.
    for action, data in [
        ('playback.tracks', {}),
        ('playback.select_track', {'kind': 'audio', 'origin': 'embedded', 'index': 0}),
        ('playback.load_subtitle', {'path': str(episode.with_suffix('.srt')), 'activate': False}),
        ('playback.remove_subtitle', {'path': str(episode.with_suffix('.srt'))}),
        ('playback.stream_options', {}), ('playback.select_stream', {'quality': 'original'}),
        ('playback.playlist', {}), ('playback.switch_episode', {'direction': 'next'}),
    ]:
        call(action, data)
    # Directory authorization is a native human picker; exercise validation
    # without leaving a modal sheet or sending OS keystrokes to the user.
    call('playback.authorize_directory', {'initialDirectory': ''})
    call('playback.close')
    script = artifacts / 'external-player'
    args_path = artifacts / 'external-args.txt'
    script.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > ' + repr(str(args_path)) + '\nexec sleep 20\n')
    script.chmod(0o755)
    setting('player.externalPath', str(script))
    setting('player.externalType', 'generic')
    setting('player.externalEnabled', True)
    call('playback.open', {'path': str(episode)})
    external_state = state()
    call('playback.info')
    call('playback.external', {'command': 'state'})
    call('playback.external_state')
    call('playback.external.danmaku_state')
    call('playback.external.danmaku', {'offsetSeconds': 0})
    shot('external-ui')
    assert external_state['player'] == 'external', external_state
    assert external_state['positionMs'] is None and external_state['paused'] is None
    assert args_path.read_text().splitlines() == [str(episode)]
    call('playback.close')
    os.kill(external_state['external']['pid'], signal.SIGTERM)
    # Detection is noninteractive and does not launch or focus a player.
    call('playback.external_player_path', {'command': 'detect'})
finally:
    setting('player.externalEnabled', False)
    for key in settings[1:]:
        if saved.get(key) is not None:
            setting(key, saved[key])
    if saved.get(settings[0]):
        setting(settings[0], True)
    call('playback.close')
    if original_kernel is not None:
        setting('player.kernel', original_kernel)
    (root / 'host.json').write_text(json.dumps(extension('player.host', op='lifecycles'), indent=2))
    (root / 'perf.json').write_text(json.dumps(extension('player.perf', op='read'), indent=2))
    extension('nextui', op='status')
    called = {r['action'] for r in receipts}
    (root / 'coverage.json').write_text(json.dumps({
        'actions': len(catalog['actions']), 'called': sorted(called),
        'missing': sorted(a['id'] for a in catalog['actions'] if a['id'] not in called),
        'directoryPicker': 'only invalid-input validation; native selection requires a human',
    }, ensure_ascii=False, indent=2))
    for artifact in artifacts.iterdir():
        if artifact.is_file() and artifact.name != 'external-player':
            shutil.copyfile(artifact, root / artifact.name)
