#!/usr/bin/env python3
"""K 线真实实例验收。整段启动、静音、驱动、截图与关闭都在 mac-lab 锁内：

    lockf -k ~/.nipa-next/mac-lab.lock python3 tool/next/kernel_lab.py <运行目录> <模式> [参数]

模式：
  smoke KERNEL…   每个内核各打开一次（Sintel 与第 12 集），验收 1 的单次版；
  play KERNEL N   验收 1：每个内核、每个片源 N 次（默认 10）；
  swap N          验收 2：mdk、erika、media_kit 之间循环换 N 次（默认 50），穿插跳转和暂停；
  setting         验收 3：播放中 settings.set player.kernel；
  rapid KERNEL N  验收 5：快速开关 N 次；
  facts           验收 4：四个内核的 playback.kernel（Erika 另有 listMethods）。

看门狗：每个对实例的请求若 15 秒没有应答，就对实例采样、TERM、KILL，记录后中止。
实例启动后立刻静音；从不对窗口做置顶、移动、缩放，不抢前台。
"""
import json
import os
from pathlib import Path
import random
import re
import signal
import subprocess
import sys
import time
import urllib.parse
import urllib.request

HOME = Path.home()
ROOT = Path(__file__).resolve().parents[2]
PROFILE = HOME / 'Library/Application Support/NipaPlay/LabProfiles/core-lab-k'
MEDIA = HOME / 'Library/Application Support/NipaPlay/LabProfiles/e2e42b/data/downloads'
SINTEL = MEDIA / 'sintel-4k-official/Sintel.2010.2160p.mkv'
SINTEL_SRT = next((MEDIA / 'sintel-4k-official').glob('*.srt'), None)
EPISODE = next((MEDIA / 'b621baa4d7644b738413c315e504e5d83b867ba5').glob('*.mkv'))
TOOLS = HOME / '.nipa-next/player-core-k-runs/tools'
# AVFoundation (video_player's backend on macOS) does not open Matroska
# ("This media format is not supported", OSStatus -12847): that kernel plays
# the same two media remuxed to MP4 (streams copied, not re-encoded).
MP4 = {'sintel': HOME / '.nipa-next/player-core-k-runs/media/sintel.mp4',
       'episode12': HOME / '.nipa-next/player-core-k-runs/media/episode12.mp4'}


def media_for(kernel, name):
    if kernel == 'video_player':
        return MP4[name]
    return SINTEL if name == 'sintel' else EPISODE

SETTING = {'erika': 'erika', 'media_kit': 'mediaKit', 'video_player': 'videoPlayer', 'mdk': 'mdk'}
RUN = Path(sys.argv[1]).resolve()
RUN.mkdir(parents=True, exist_ok=True)
MODE = sys.argv[2] if len(sys.argv) > 2 else 'smoke'
ARGS = sys.argv[3:]
# A copy of the build can be driven while the next one is made (KERNEL_LAB_APP).
app = Path(os.environ.get('KERNEL_LAB_APP') or ROOT / 'build/macos/Build/Products/Debug/NipaPlay.app') / 'Contents/MacOS/NipaPlay'
log = RUN / 'run.log'
out = RUN / 'results.jsonl'
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
url = None
iso = None
PID = None


class Watchdog(Exception):
    pass


def record(kind, **data):
    row = {'kind': kind, 'at': round(time.time(), 3), **data}
    with out.open('a') as f:
        f.write(json.dumps(row, ensure_ascii=False) + '\n')
    print(json.dumps(row, ensure_ascii=False)[:600], flush=True)


def watchdog(method):
    """事件循环 15 秒没有应答：采样、kill 实例并记录，然后中止整个实验。"""
    record('watchdog', method=method, pid=PID)
    if PID:
        subprocess.run(['sample', str(PID), '3', '-file', str(RUN / 'watchdog-sample.txt')],
                       capture_output=True, timeout=30)
        for sig in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.kill(PID, sig)
            except ProcessLookupError:
                break
            time.sleep(3)
    raise Watchdog(method)


def rpc(method, **params):
    try:
        with opener.open(url + method + '?' + urllib.parse.urlencode(params), timeout=15) as response:
            data = json.load(response)
    except (TimeoutError, OSError) as error:
        if 'timed out' in str(error) or isinstance(error, TimeoutError):
            watchdog(method)
        raise
    if 'error' in data:
        raise RuntimeError(data['error'])
    return data['result']


def gui(action, data=None, strict=False):
    result = rpc('ext.nipaplay.nextui', isolateId=iso, op='guicall', action=action,
                 input=json.dumps(data or {}, ensure_ascii=False))
    result = result.get('result', result)
    if strict and 'failure' in result:
        raise RuntimeError('%s: %s' % (action, result['failure']))
    return result


def state():
    result = gui('playback.state')
    return result.get('state', result)


def host(op='facts', **extra):
    return rpc('ext.nipaplay.player.host', isolateId=iso, op=op, **extra)


def setting(key, value):
    return gui('settings.set', {'key': key, 'value': value, 'reason': 'K 线内核验收'})


def effective(key):
    return gui('settings.get', {'key': key})


def use(kernel):
    reply = setting('player.kernel', SETTING[kernel])
    if 'failure' in reply:
        raise RuntimeError('settings.set player.kernel: %s' % reply)


def pngstats(path, *region):
    reply = subprocess.run([str(TOOLS / 'pngstats'), str(path), *map(str, region)],
                           capture_output=True, text=True, timeout=60)
    try:
        return json.loads(reply.stdout)
    except json.JSONDecodeError:
        return {'error': reply.stdout + reply.stderr}


def shot(name):
    """窗口自己的合成画面（原生视频在透明洞下面）与 Flutter 自己画的那一层，各取中心区域的像素统计。"""
    # The app writes into its own profile; the copy is the run's.
    inside = PROFILE / 'temp/k-shots'
    inside.mkdir(parents=True, exist_ok=True)
    window = RUN / (name + '-window.png')
    reply = rpc('ext.nipaplay.player.windowShot', isolateId=iso, path=str(inside / (name + '.png')))
    if (inside / (name + '.png')).exists():
        subprocess.run(['cp', str(inside / (name + '.png')), str(window)])
    composed = pngstats(window, 0.2, 0.2, 0.6, 0.5) if window.exists() else None
    flutter = subprocess.run(['./nipa', 'call', 'ui.capture', '{}'], cwd=PROFILE / 'harness',
                             capture_output=True, text=True, timeout=60)
    layer = None
    try:
        path = json.loads(flutter.stdout)['result']['path']
        layer = pngstats(path, 0.2, 0.2, 0.6, 0.5)
        subprocess.run(['cp', path, str(RUN / (name + '-flutter.png'))])
    except Exception as error:
        layer = {'error': str(error)}
    record('shot', name=name, reply=reply, composed=composed, flutterLayer=layer)
    return composed, layer


def alive():
    try:
        os.kill(PID, 0)
        return True
    except ProcessLookupError:
        return False


def wait_playing(seconds=10):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        s = state()
        if s.get('status') in ('playing', 'paused') or s.get('error'):
            return s
        time.sleep(0.1)
    return state()


def check(kernel, name, iteration, picture=False):
    """验收 1 的一次：打开，跳到 70%，暂停和恢复，关闭，重开续播。"""
    path = media_for(kernel, name)
    use(kernel)
    # 从头开始：这次的续播起点不受上一次影响。
    start = time.monotonic()
    opened = gui('playback.open', {'path': str(path), 'startPositionMs': 10000})
    first = wait_playing()
    took = time.monotonic() - start
    row = dict(kernel=kernel, media=name, iteration=iteration, openSeconds=round(took, 2),
               kernelId=(first.get('kernel') or {}).get('id'), status=first.get('status'),
               positionMs=first.get('positionMs'), durationMs=first.get('durationMs'),
               error=first.get('error'), sessionId=first.get('sessionId'))
    ok = row['kernelId'] == kernel and row['status'] == 'playing' and not row['error']
    if not ok:
        record('open_failed', **row, reply=opened)
        gui('playback.close')
        return False
    target = int(first['durationMs'] * .7)
    gui('playback.seek', {'positionMs': target}, strict=True)
    a = state()
    # It goes on from there: how long until it has moved half a second.
    waited = time.monotonic()
    while True:
        b = state()
        if b.get('positionMs', 0) >= a.get('positionMs', 0) + 500 or time.monotonic() - waited > 5:
            break
        time.sleep(0.05)
    advance_ms = round((time.monotonic() - waited) * 1000)
    gui('playback.set_paused', {'paused': True}, strict=True)
    paused = state()
    time.sleep(.5)
    still = state()
    gui('playback.set_paused', {'paused': False}, strict=True)
    time.sleep(.6)
    resumed = state()
    facts = gui('playback.kernel', {})
    if picture:
        row['picture'] = shot('%s-%s' % (kernel, name))
        if kernel == 'erika':
            first_stats = ((facts.get('erika') or {}).get('frames') or {})
            time.sleep(1)
            again = gui('playback.kernel', {})
            row['erikaFrames'] = (first_stats, ((again.get('erika') or {}).get('frames') or {}))
            row['erikaMethods'] = gui('playback.kernel_invoke', {
                'sessionId': first['sessionId'], 'method': 'listMethods'}).get('supported')
    before_close = state()
    gui('playback.close')
    gui('playback.open', {'path': str(path)})
    reopened = wait_playing()
    record('verify', **row,
           seekErrorMs=a.get('positionMs', 0) - target,
           advancing=b.get('positionMs', 0) >= a.get('positionMs', 0) + 500, advanceMs=advance_ms,
           paused=paused.get('status'), pauseDeltaMs=still.get('positionMs', 0) - paused.get('positionMs', 0),
           resumed=resumed.get('status'),
           resumeErrorMs=reopened.get('positionMs', 0) - before_close.get('positionMs', 0),
           kernelVersion=(facts.get('kernel') or {}).get('version'),
           blocked=blocked())
    gui('playback.close')
    return True


def blocked():
    return [line for line in log.read_text(errors='replace').splitlines() if 'main isolate blocked' in line]


EP_ASS = HOME / '.nipa-next/player-core-k-runs/media/episode12-jptc.ass'


def subtitle_facts():
    current = host().get('current') or {}
    subtitles = (current.get('tracks') or {}).get('subtitles') or {}
    return {'selected': subtitles.get('selected'), 'presented': subtitles.get('presented'),
            'presentedIsSelected': subtitles.get('presentedIsSelected'), 'failure': subtitles.get('failure'),
            'audio': (current.get('tracks') or {}).get('audio')}


def swap_loop(count, media='sintel', subtitle='srt'):
    """验收 2：40% 处播放（挂着外挂字幕），在 mdk、erika、media_kit 之间循环换，穿插跳转和暂停。"""
    use('mdk')
    path = media_for('mdk', media)
    duration = 888032 if media == 'sintel' else 1418065
    gui('playback.open', {'path': str(path), 'startPositionMs': int(duration * .4)})
    wait_playing()
    file = SINTEL_SRT if subtitle == 'srt' else EP_ASS
    record('mount', file=str(file), reply=gui('playback.load_subtitle', {'path': str(file)}), facts=subtitle_facts())
    paused_now = False
    failures = 0
    cycle = ['erika', 'media_kit', 'mdk']
    for i in range(count):
        before = state()
        kernel = cycle[i % 3]
        started = time.monotonic()
        reply = gui('playback.reopen_with_kernel', {'sessionId': before['sessionId'], 'kernel': kernel})
        took = time.monotonic() - started
        after = state()
        preserved = reply.get('preserved') or {}
        # Where it should be: where it was, plus what ran while it swapped (nothing while paused).
        position = preserved.get('positionMs') or {}
        expected = position.get('before', before.get('positionMs', 0))
        # Paused while it swaps, it plays on only once it has: where it was, to the second.
        pos_error = after.get('positionMs', 0) - expected
        facts = subtitle_facts()
        presented = facts.get('presented') or []
        good = (reply.get('opened') is True and (after.get('kernel') or {}).get('id') == kernel
                and abs(pos_error) <= 1000
                and (after.get('status') == 'paused') == paused_now and alive()
                and facts.get('presentedIsSelected') is True and len(presented) == 1)
        if not good:
            failures += 1
        record('swap', iteration=i, kernel=kernel, seconds=round(took, 2), positionErrorMs=round(pos_error),
               status=after.get('status'), expectedPaused=paused_now, ok=good,
               sessionKept=after.get('sessionId') == before.get('sessionId'),
               audioTrack=preserved.get('audioTrack'), subtitleTrack=preserved.get('subtitleTrack'),
               presented=presented, failure=reply.get('failure'))
        if i % 5 == 4:
            target = int(duration * (.3 + (i % 20) / 50))
            gui('playback.seek', {'positionMs': target}, strict=True)
            again = state()
            record('swap_seek', iteration=i, target=target, landedMs=again.get('positionMs'))
        if i % 10 == 9:
            paused_now = not paused_now
            gui('playback.set_paused', {'paused': paused_now}, strict=True)
        time.sleep(0.3)
    record('swap_done', count=count, media=media, subtitle=subtitle, failures=failures, alive=alive())
    gui('playback.close')


def rapid_loop(kernel, count):
    use(kernel)
    random_wait = random.Random(5)
    failures = 0
    for i in range(count):
        started = time.monotonic()
        try:
            gui('playback.open', {'path': str(media_for(kernel, 'sintel' if i % 2 == 0 else 'episode12')), 'startPositionMs': 20000})
            time.sleep(random_wait.random() * 0.8)
            gui('playback.close')
        except (RuntimeError, Watchdog) as error:
            failures += 1
            record('rapid_error', iteration=i, error=str(error))
            if isinstance(error, Watchdog):
                raise
        if not alive():
            record('rapid_crashed', iteration=i)
            raise RuntimeError('实例消失了')
        if i % 10 == 9:
            record('rapid', kernel=kernel, done=i + 1, failures=failures, seconds=round(time.monotonic() - started, 2))
    facts = host()
    record('rapid_done', kernel=kernel, count=count, failures=failures, current=facts.get('current'),
           lease=facts.get('lease'), blocked=blocked())
    lifecycles = host('lifecycles').get('lifecycles', [])
    timeouts = [l for l in lifecycles if l.get('releaseTimeouts')]
    late = sum(l.get('lateCallbacks', 0) for l in lifecycles)
    record('rapid_lifecycles', instances=len(lifecycles), withReleaseTimeouts=len(timeouts), lateCallbacks=late,
           releaseMs=sorted(round(l.get('releaseUs', 0) / 1000) for l in lifecycles)[-5:])


def paused_check(kernel):
    """暂停时出帧：以暂停状态打开画面不黑；暂停时跳到 70%，画面是那一帧。"""
    use(kernel)
    for name in ('sintel', 'episode12'):
        path = media_for(kernel, name)
        opened = host('open', path=str(path), paused='1', startMs=str(120000))
        time.sleep(1.5)
        a = state()
        record('paused_state', state=a, host={k: v for k, v in (host().get('current') or {}).items() if k in ('phase', 'phaseTimesMs', 'fault', 'tracks')})
        if a.get('error') or a.get('status') != 'paused':
            record('paused_failed', kernel=kernel, media=name, error=a.get('error'))
            gui('playback.close')
            continue
        open_shot = shot('%s-%s-paused-open' % (kernel, name))
        target = int(a['durationMs'] * .7)
        seek_reply = gui('playback.seek', {'positionMs': target}, strict=True)
        record('paused_seek_reply', reply=seek_reply)
        time.sleep(1.5)
        b = state()
        seek_shot = shot('%s-%s-paused-seek70' % (kernel, name))
        record('paused', kernel=kernel, media=name, openedMs=opened.get('openedMs'), statusAfterOpen=a.get('status'),
               positionAfterOpen=a.get('positionMs'), statusAfterSeek=b.get('status'), positionAfterSeek=b.get('positionMs'),
               targetMs=target, openStats=open_shot[0], seekStats=seek_shot[0])
        gui('playback.close')


def subtitles_check(kernel):
    """字幕：Sintel 只显示被选中的那一条，切换生效；第 12 集的 ASS 正常显示。"""
    use(kernel)
    sintel = media_for(kernel, 'sintel')
    host('open', path=str(sintel), paused='1', startMs=str(131000))
    time.sleep(1.5)
    tracks = gui('playback.tracks')
    record('tracks', kernel=kernel, tracks=tracks)
    embedded = [t for t in (tracks.get('subtitles') or tracks.get('subtitle') or []) if t.get('origin') == 'embedded']
    english = next((t for t in embedded if 'en' in (t.get('language') or '').lower()), embedded[1] if len(embedded) > 1 else None)
    state0 = state()
    record('subtitle_start', kernel=kernel, facts=subtitle_facts(), status=state0.get('status'))
    if english is not None:
        reply = gui('playback.select_track', {'kind': 'subtitle', 'origin': 'embedded', 'index': english['index']})
        time.sleep(1)
        gui('playback.seek', {'positionMs': 131100}, strict=True)
        time.sleep(1.2)
        record('subtitle_english', kernel=kernel, reply=reply, facts=subtitle_facts(), text=host('text'))
        shot('%s-sintel-english' % kernel)
        reply = gui('playback.select_track', {'kind': 'subtitle', 'origin': 'embedded', 'index': -1})
        time.sleep(1)
        record('subtitle_off', kernel=kernel, reply=reply, facts=subtitle_facts(), text=host('text'))
        shot('%s-sintel-off' % kernel)
    gui('playback.load_subtitle', {'path': str(SINTEL_SRT)})
    gui('playback.seek', {'positionMs': 123500}, strict=True)
    time.sleep(1.2)
    record('subtitle_srt', kernel=kernel, facts=subtitle_facts())
    shot('%s-sintel-srt' % kernel)
    gui('playback.close')
    episode = media_for(kernel, 'episode12')
    host('open', path=str(episode), paused='1', startMs=str(120000))
    time.sleep(1.5)
    tracks = gui('playback.tracks')
    record('tracks', kernel=kernel, media='episode12', tracks=tracks)
    embedded = [t for t in (tracks.get('subtitles') or tracks.get('subtitle') or []) if t.get('origin') == 'embedded']
    if embedded:
        reply = gui('playback.select_track', {'kind': 'subtitle', 'origin': 'embedded', 'index': embedded[0]['index']})
        time.sleep(1)
        gui('playback.seek', {'positionMs': 130000}, strict=True)
        time.sleep(1.5)
        record('subtitle_ass', kernel=kernel, reply=reply, facts=subtitle_facts(), text=host('text'))
        shot('%s-episode12-ass' % kernel)
    gui('playback.close')


def mdk_file_plan():
    """MDK + 字幕库记的外挂 ASS 进打开计划（Sintel）：打开会不会成。"""
    ass = HOME / '.nipa-next/erika-followups-runs/data/sintel.zh.ass'
    use('erika')
    gui('playback.open', {'path': str(SINTEL), 'startPositionMs': 120000})
    wait_playing()
    record('off', reply=gui('playback.select_track', {'kind': 'subtitle', 'origin': 'embedded', 'index': -1}), facts=subtitle_facts())
    gui('playback.close')
    use('mdk')
    gui('playback.open', {'path': str(SINTEL), 'startPositionMs': 120000})
    s = wait_playing()
    record('mdk_plain', status=s.get('status'), error=s.get('error'), facts=subtitle_facts())
    record('mdk_load', reply=gui('playback.load_subtitle', {'path': str(ass)}), facts=subtitle_facts())
    time.sleep(1)
    gui('playback.close')
    gui('playback.open', {'path': str(SINTEL), 'startPositionMs': 120000})
    s = wait_playing()
    record('mdk_file_plan', status=s.get('status'), error=s.get('error'), facts=subtitle_facts())
    gui('playback.close')


def setting_check():
    """验收 3：播放中保存内核设置，当前播放不受影响，下次打开用新内核。"""
    use('mdk')
    gui('playback.open', {'path': str(SINTEL), 'startPositionMs': 30000})
    s = wait_playing()
    record('setting_before', kernel=(s.get('kernel') or {}).get('id'), effective=effective('player.kernel'))
    use('erika')
    a = state()
    time.sleep(1.5)
    b = state()
    record('setting_during', kernelBefore=(a.get('kernel') or {}).get('id'), kernelAfter=(b.get('kernel') or {}).get('id'),
           advancing=b.get('positionMs', 0) > a.get('positionMs', 0), status=b.get('status'),
           effective=effective('player.kernel'), hwEffective=effective('player.useHardwareDecoder'))
    gui('playback.close')
    gui('playback.open', {'path': str(SINTEL), 'startPositionMs': 30000})
    c = wait_playing()
    record('setting_next', kernel=(c.get('kernel') or {}).get('id'), effective=effective('player.kernel'))
    gui('playback.close')
    use('mdk')


def facts_check():
    """验收 4：四个内核都能读到版本和快照，Erika 能 listMethods。"""
    for kernel in SETTING:
        use(kernel)
        gui('playback.open', {'path': str(media_for(kernel, 'sintel')), 'startPositionMs': 30000})
        s = wait_playing()
        facts = gui('playback.kernel', {'properties': ['hwdec-current']} if kernel == 'media_kit' else {})
        row = dict(kernel=kernel, kernelId=(s.get('kernel') or {}).get('id'), version=(facts.get('kernel') or {}).get('version'),
                   snapshotKeys=len(facts.get('snapshot') or {}), controls=facts.get('controls'),
                   properties=facts.get('properties'), decoders=facts.get('decoders'))
        if kernel == 'erika':
            methods = gui('playback.kernel_invoke', {'sessionId': s['sessionId'], 'method': 'listMethods'})
            row['listMethods'] = {k: methods.get(k) for k in ('supported', 'error')}
            result = methods.get('result') or {}
            row['methods'] = [m.get('name') for m in result.get('methods', [])][:80]
            erika = facts.get('erika') or {}
            row['erikaDecoder'] = erika.get('decoder')
            row['erikaFrames'] = erika.get('frames')
        record('facts', **row)
        info = gui('playback.info', {})
        record('info', kernel=kernel, decoder=info.get('decoder'), video=info.get('video'), kernelFacts=info.get('kernel'))
        gui('playback.close')


env = dict(os.environ, NIPAPLAY_LAB_DHT='0', NIPAPLAY_PROFILE='core-lab-k',
           CODEX_CA_CERTIFICATE=str(PROFILE / 'system-ca.pem'), SSL_CERT_FILE=str(PROFILE / 'system-ca.pem'))
with log.open('w') as output:
    process = subprocess.Popen([str(app)], cwd=PROFILE, env=env, stdout=output, stderr=subprocess.STDOUT)
(RUN / 'pid').write_text(str(process.pid))
PID = process.pid
try:
    for _ in range(120):
        if process.poll() is not None:
            raise RuntimeError('实验实例提前退出')
        matches = re.findall(r'Dart VM service is listening on (http://[^\s]+)', log.read_text(errors='replace'))
        if matches:
            url = matches[-1]
            break
        time.sleep(1)
    time.sleep(12)
    subprocess.run(['python3', str(HOME / '.nipa-next/labmute.py'), str(log)], check=True, timeout=60)
    iso = next(i['id'] for i in rpc('getVM')['isolates'] if i['name'] == 'main')
    record('front', value=subprocess.check_output(['lsappinfo', 'front'], text=True).strip(), pid=PID)
    rpc('ext.nipaplay.player.perf', isolateId=iso, op='reset', frames='false')
    if MODE in ('smoke', 'play'):
        kernels = [k for k in ARGS if k in SETTING] or list(SETTING)
        count = next((int(a) for a in ARGS if a.isdigit()), 1 if MODE == 'smoke' else 10)
        for kernel in kernels:
            for name in ('sintel', 'episode12'):
                for iteration in range(count):
                    check(kernel, name, iteration, picture=iteration == 0)
    elif MODE == 'paused':
        for kernel in ARGS or SETTING:
            paused_check(kernel)
    elif MODE == 'subtitles':
        for kernel in ARGS or SETTING:
            subtitles_check(kernel)
    elif MODE == 'prep':
        # prep sintel|episode12 off|embedded N|file PATH: what the subtitle
        # library records for that media, set through Erika.
        name, kind = ARGS[0], ARGS[1]
        use('erika')
        gui('playback.open', {'path': str(media_for('erika', name)), 'startPositionMs': 5000})
        wait_playing()
        if kind == 'off':
            reply = gui('playback.select_track', {'kind': 'subtitle', 'origin': 'embedded', 'index': -1})
        elif kind == 'embedded':
            reply = gui('playback.select_track', {'kind': 'subtitle', 'origin': 'embedded', 'index': int(ARGS[2])})
        else:
            reply = gui('playback.load_subtitle', {'path': ARGS[2]})
        time.sleep(1)
        record('prep', reply=reply, facts=subtitle_facts())
        gui('playback.close')
    elif MODE == 'mdkfile':
        mdk_file_plan()
    elif MODE == 'swap':
        swap_loop(int(ARGS[0]) if ARGS else 50, ARGS[1] if len(ARGS) > 1 else 'sintel',
                  ARGS[2] if len(ARGS) > 2 else 'srt')
    elif MODE == 'setting':
        setting_check()
    elif MODE == 'rapid':
        rapid_loop(ARGS[0], int(ARGS[1]) if len(ARGS) > 1 else 100)
    elif MODE == 'facts':
        facts_check()
    record('perf', reply=rpc('ext.nipaplay.player.perf', isolateId=iso, op='read'))
    record('alive', reply=host())
    record('blocked', lines=blocked())
finally:
    if process.poll() is None:
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            # Preserve the failure: never silently report a stuck teardown as success.
            record('shutdown_timeout', pid=process.pid)
            raise
    record('closed', code=process.returncode)
