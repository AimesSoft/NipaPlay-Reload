"""accept-kernels.py [kernel ...] -- for each kernel: reopen the playing media on it, check seek, pause/resume,
subtitle track selection, danmaku and ui.capture, and keep the capture (D:\\nipaplay-next\\win-next\\lab\\winlab\\shots).
Needs the winlab instance running with Sintel.2010.720p.mkv open (accept-open.json)."""
import json, os, shutil, subprocess, sys, tempfile, time
NIPA = r'D:\nipaplay-next\win-next\lab\winlab\harness\nipa'
SHOTS = r'D:\nipaplay-next\win-next\lab\winlab\shots'
os.makedirs(SHOTS, exist_ok=True)
env = dict(os.environ, PYTHONUTF8='1')

def call(action, data=None, view=False):
    f = tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, encoding='utf-8')
    f.write(json.dumps(data or {})); f.close()
    r = subprocess.run([sys.executable, NIPA, 'query' if view else 'call', action, '@' + f.name], capture_output=True, text=True, encoding='utf-8', env=env)
    os.unlink(f.name)
    try:
        return json.loads(r.stdout)
    except Exception:
        return {'status': 'unparsed', 'stdout': r.stdout[:500], 'stderr': r.stderr[:500]}

def state():
    r = call('playback.state')
    return (r.get('result') or {}).get('state', r.get('result') or {})

def wait_playing(session, secs=20):
    r = call('playback.wait', {'sessionId': session, 'until': 'playing', 'timeoutMs': secs * 1000})
    return (r.get('result') or {})

kernels = sys.argv[1:] or ['mdk', 'media_kit', 'erika', 'video_player']
results = {}
for kernel in kernels:
    out = {}
    results[kernel] = out
    st = state()
    sid = st.get('sessionId')
    if st.get('kernel', {}).get('id') != kernel:
        r = call('playback.reopen_with_kernel', {'sessionId': sid, 'kernel': kernel})
        out['reopen'] = r.get('status') if r.get('status') == 'completed' else r
        time.sleep(3)
    st = state()
    sid = st.get('sessionId')
    out['kernel'] = st.get('kernel')
    out['status'] = st.get('status'); out['hasVideo'] = st.get('hasVideo'); out['durationMs'] = st.get('durationMs')
    w = wait_playing(sid)
    out['wait'] = w.get('result') or w.get('status')
    # seek
    r = call('playback.seek', {'positionMs': 20000})
    time.sleep(2)
    st = state()
    out['seek20s'] = {'positionMs': st.get('positionMs'), 'ok': (st.get('positionMs') or 0) >= 19000, 'status': st.get('status')}
    # pause / resume
    call('playback.set_paused', {'paused': True}); time.sleep(1)
    p = state().get('paused')
    call('playback.set_paused', {'paused': False}); time.sleep(1)
    out['pause_resume'] = {'paused_after_pause': p, 'paused_after_resume': state().get('paused')}
    # subtitles: the sidecar one is seen on the 17-20 s cue; embedded English selected by index 1
    r = call('playback.select_track', {'kind': 'subtitle', 'origin': 'embedded', 'index': 1})
    out['select_embedded_eng'] = r.get('status') if r.get('status') == 'completed' else r
    time.sleep(1)
    tracks = (call('playback.tracks').get('result') or {}).get('tracks', [])
    out['subtitles_selected'] = [(t.get('origin'), t.get('index'), t.get('language'), t.get('presented')) for t in tracks if t.get('kind') == 'subtitle' and t.get('selected')]
    # danmaku
    d = call('danmaku.tracks', {'current': True})
    res = d.get('result') or {}
    out['danmaku_tracks'] = [(t.get('origin'), t.get('platform'), t.get('loaded'), t.get('enabled'), t.get('count')) for t in (res.get('tracks') or res.get('bindings') or [])][:4]
    # capture
    call('playback.seek', {'positionMs': 33500}); time.sleep(2.5)
    c = call('ui.capture')
    cr = c.get('result') or {}
    out['capture'] = {k: cr.get(k) for k in ('method', 'surface', 'includesVideo', 'includesNativeVideo', 'video', 'videoFailure', 'windowCaptureFailure', 'width', 'height')}
    if cr.get('path'):
        dst = os.path.join(SHOTS, 'kernel-%s.png' % kernel)
        shutil.copyfile(cr['path'], dst)
        out['capture']['file'] = dst
    # playback.capture (the player's own frame)
    pc = call('playback.capture', {'kind': 'screenshot'})
    out['playback_capture'] = pc.get('status') if pc.get('status') == 'completed' else pc.get('error') or pc
print(json.dumps(results, ensure_ascii=False, indent=1))
