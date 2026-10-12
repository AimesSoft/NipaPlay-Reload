#!/usr/bin/env python3
"""Quiet worktree-only X39 observations. Each phase has its own disposable profile."""
import gzip, json, os, re, shutil, sqlite3, subprocess, sys, time
from pathlib import Path
import urllib.parse, urllib.request
from x23_vm import LabVM

workspace = Path(__file__).resolve().parents[2]
mode = sys.argv[1]
resume = len(sys.argv)>2 and sys.argv[2]=='--resume'
assert mode in ('body', 'body-projection', 'agent')
assert not resume or mode=='body'
evidence = workspace / 'docs/next/evidence/x39' / mode
evidence.mkdir(parents=True, exist_ok=True)
profile = next(x['value']['profileName'] for x in json.loads((evidence/'operations.json').read_text()) if x['label']=='instance') if resume else 'x39-' + mode + '-' + str(os.getpid())
assert profile.startswith('x39-'+mode+'-')
root = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
assert root.exists() if resume else not root.exists()
root.mkdir(mode=0o700,exist_ok=resume)
home = root / 'codex-home'; home.mkdir(mode=0o700,exist_ok=resume)
source = Path('/Volumes/Media/长安十二时辰')
app = vm = None
records = json.loads((evidence/'operations.json').read_text()) if resume else []
endpoint = None
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
secrets = []

def clean(value):
    if isinstance(value, str):
        for secret in secrets:
            value = value.replace(secret, '[REDACTED]')
        return value
    if isinstance(value, dict): return {k: clean(v) for k,v in value.items()}
    if isinstance(value, list): return [clean(v) for v in value]
    return value

def record(label, value):
    records.append({'at': time.time(), 'label': label, 'value': clean(value)})
    (evidence / 'operations.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, flush=True)
    return value

def call(action, inputs, save=True):
    req = urllib.request.Request(endpoint['url'], data=json.dumps({
        'operation':'call','action':action,'input':inputs}).encode(), headers={
        'Content-Type':'application/json', 'Authorization':'Bearer '+endpoint['token']})
    started = time.monotonic()
    with opener.open(req, timeout=240) as response: value = json.load(response)
    if save: record(action, {'input':inputs,'seconds':time.monotonic()-started, **value})
    if value['status'] != 'completed': raise RuntimeError(action + ': ' + json.dumps(clean(value),ensure_ascii=False))
    return value['result']

def wait_job(job):
    deadline = time.monotonic()+420
    while time.monotonic()<deadline:
        v=call('task.get', {'jobId':job['jobId']}, save=False)['job']
        if v['state'] in ('succeeded','failed','cancelled'):
            record('job-completed',v); assert v['state']=='succeeded',v; return v
        assert app.poll() is None
        time.sleep(.3)
    raise RuntimeError('Job observation deadline')

def capture(name):
    v=call('ui.capture',{})
    subprocess.run(['sips','-s','format','jpeg',v['path'],'--out',str(evidence/(name+'.jpg'))],capture_output=True,check=True)

def query(view): return call('state.query',{'view':view,'limit':200})['rows']

def wait_tracks(count):
    started=time.monotonic(); deadline=started+420
    while time.monotonic()<deadline:
        rows=call('state.query',{'view':'danmaku.bindings','limit':200},save=False)['rows']
        local=[r for r in rows if r.get('localFile',{}).get('available')]
        if len(local)==count:
            record('sidecar-ready',{'seconds':time.monotonic()-started,'count':len(local)})
            return record('sidecar-bindings',rows)
        time.sleep(.5)
    raise RuntimeError('Sidecar observation deadline')

try:
    config=(Path.home()/'.codex/config.toml').read_text()
    config=re.sub(r'(?m)^model\s*=.*$','model = "deepseek-v4.1-flash"',config,count=1)
    (home/'config.toml').write_text(config); (home/'config.toml').chmod(0o600)
    shutil.copy2(Path.home()/'.codex/auth.json',home/'auth.json')
    if not resume: (home/'skills').symlink_to(Path.home()/'.codex/skills',target_is_directory=True)
    shutil.copy2('/etc/ssl/cert.pem',root/'system-ca.pem')
    # Extract possible credentials solely for evidence redaction; never print them.
    auth=json.loads((home/'auth.json').read_text())
    def collect(v):
        if isinstance(v,dict):
            for key,x in v.items():
                if isinstance(x,str) and any(k in key.lower() for k in ['token','secret','api_key','password']): secrets.append(x)
                else: collect(x)
    collect(auth)
    for v in re.findall(r'(?im)^\s*(?:[a-z_]*(?:token|secret|api_key|password)[a-z_]*)\s*=\s*"([^"]+)"',config): secrets.append(v)
    prefs={'flutter.labs_enable_agent_endpoint':True,'flutter.labs_use_next_interface':True,
        'flutter.next_harness_path':str(root/'harness'),'flutter.auto_sync_enabled':False,
        'flutter.downloader_enabled':False,'flutter.player_volume':0.0,
        'flutter.danmaku_auto_load_strategy':'local','flutter.skip_danmaku_matching':True}
    if not resume: (root/'preferences.json').write_text(json.dumps(prefs))
    harness=root/'harness'
    if not resume: shutil.copytree(workspace/'assets/next/harness',harness)
    (harness/'nipa').chmod(0o755)
    subprocess.run(['git','init','--quiet','--template=','--initial-branch=main'],cwd=harness,check=True)
    with (harness/'AGENTS.md').open('a') as stream:
        stream.write('\n## 本次实验环境\n这是隔离实验，仅当前 harness 与连接实例。'
          '/Volumes/Media 是用户授权的只读 SMB 挂载；不写、不改名、不删、不复制整部，不寻找账号、不重新挂载。'
          '不启动或查找其他应用，不访问钥匙串或真实应用数据，不激活窗口、不点击、不重启；实例保持安静。'
          '工作文件写在当前 harness。\n')
    if mode=='body-projection':
        prior=json.loads((workspace/'docs/next/evidence/x39/agent/operations.json').read_text())
        own=next(x['value'] for x in prior if x['label']=='instance')
        assert own['profileName'].startswith('x39-agent-')
        original=Path.home()/'Library/Application Support/NipaPlay/LabProfiles'/own['profileName']/'data/next'
        target=root/'data/next'; target.mkdir(parents=True)
        with sqlite3.connect((original/'next.db').as_uri()+'?mode=ro',uri=True) as db:
            with sqlite3.connect(target/'next.db') as copied: db.backup(copied)
        shutil.copy2(original/'device.json',target/'device.json')
        with sqlite3.connect(target/'next.db') as db:
            # Remove active task machinery in this new observer fixture only.
            for table in ['job_events','jobs','media_scan_items','media_projection_outbox']:
                db.execute('DELETE FROM '+table)
            db.execute('UPDATE danmaku_bindings SET cache_job_id=NULL')
            db.execute('DELETE FROM media_locations WHERE locator NOT LIKE ?', (str(source)+'/%',))
        record('projection-index-snapshot',{'fromOwnedProfile':own['profileName'],'noScan':True,'noXmlCopy':True})
    hosts=['127.0.0.1','localhost']+[urllib.parse.urlparse(u).hostname for u in re.findall(r'(?m)^base_url\s*=\s*"([^"]+)"',config)]
    env=dict(os.environ,NIPAPLAY_PROFILE=profile,CODEX_HOME=str(home),
        CODEX_CA_CERTIFICATE=str(root/'system-ca.pem'),SSL_CERT_FILE=str(root/'system-ca.pem'),
        NO_PROXY=','.join(hosts),no_proxy=','.join(hosts))
    env.pop('NIPAPLAY_LAB_QUIET',None)
    log=root/('resume-app.log' if resume else 'app.log')
    (root/'endpoint.json').unlink(missing_ok=True)
    with log.open('w') as stream:
        app=subprocess.Popen([str(workspace/'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],cwd=workspace,env=env,stdout=stream,stderr=subprocess.STDOUT)
    deadline=time.monotonic()+150
    while time.monotonic()<deadline:
        assert app.poll() is None,'owned app exited'
        if (root/'endpoint.json').exists():
            try:
                endpoint=json.loads((root/'endpoint.json').read_text())
                vm=LabVM(log)
                if vm.chat('status')['header'].get('model'): break
            except (RuntimeError,OSError): pass
        time.sleep(.3)
    else: raise RuntimeError('startup observation deadline')
    secrets.append(endpoint['token'])
    record('instance',call('app.instance',{})); assert vm.rpc('getVM')['pid']==app.pid
    record('chat-header',vm.chat('status')['header'])
    call('media.library.roots.add',{'paths':[str(source)]})
    videos=sorted([p for p in source.rglob('*') if p.suffix.lower() in ('.mkv','.mp4')])
    assert len(videos)==48
    if mode!='agent':
        started=time.monotonic()
        if mode=='body-projection':
            record('projection-only',{'scanRepeated':False,'source':'Read-only snapshot of this X39 agent experiment index'})
            scan_seconds=None
        elif resume:
            done=next(x['value'] for x in records if x['label']=='job-completed')
            from datetime import datetime
            scan_seconds=(datetime.fromisoformat(done['updatedAt'].replace('Z','+00:00'))-datetime.fromisoformat(done['createdAt'].replace('Z','+00:00'))).total_seconds()
            record('body-continuation',{'scanRepeated':False,'originalPid':38454,'queueSelfWaitFixed':True})
        else:
            done=wait_job(call('media.library.scan',{'root':str(source),'requestId':profile+'-scan'})['job'])
            scan_seconds=time.monotonic()-started
        bindings=wait_tracks(48)
        record('timing',{'scanSeconds':scan_seconds,'allSidecarsSeconds':time.monotonic()-started,
          'readMsSum':sum(b['localFile']['readMs'] for b in bindings if b.get('localFile'))})
        files=query('library.files')
        # Only the body observer establishes episode links, using the real provider catalogue.
        found=call('media.metadata.search',{'provider':'bangumi','query':'长安十二时辰','kind':'tv'})
        candidates=found['results']
        record('body-catalogue-search',found)
        selected=next((x for x in candidates if x['title']=='长安十二时辰'),
          {'ref':{'provider':'bangumi','objectType':'subject','externalId':'285493','scope':''}})
        record('body-catalogue-basis',{'ref':selected['ref'],'basis':'Verified X35 catalogue identity; operator supplied only in body observer profile'})
        catalogue=call('media.metadata.get',{'ref':selected['ref']})
        record('body-catalogue',catalogue)
        record('body-ready-for-binding',{'files':len(files)})
        # These provider records carry episode refs, so the application checks the mapping atomically.
        work=catalogue['record']
        release=work
        episodes=sorted(work['episodes'],key=lambda x:float(x['number'] or 0))
        indexed=sorted(files,key=lambda x:x['locator'])
        entries=[{'kind':'file','entityId':f['fileId'],'workRef':work['ref'],
          'releaseRef':release['ref'],'episodeRefs':[e['ref']],
          'reason':'X39 body observer: numbered filename and real Bangumi episode catalogue'} for f,e in zip(indexed,episodes)]
        bound=call('media.identity.bind_batch',{'requestId':profile+'-bind','entries':entries})
        wid=bound['entries'][0]['workId']
        facts=call('media.metadata.ui_facts',{'workId':wid})
        record('body-ui-work',vm.rpc('ext.nipaplay.uiData',isolateId=vm.isolate,op='work',workId=wid))
        call('playback.open',{'path':str(videos[0])})
        deadline=time.monotonic()+120
        while time.monotonic()<deadline:
            tracks=call('playback.tracks',{},save=False)
            if any(x['kind']=='danmaku' for x in tracks['tracks']): break
            time.sleep(.5)
        record('playback.tracks',tracks)
        call('state.query',{'view':'danmaku.tracks','limit':200})
        capture('playing')
    else:
        # X35 started with three incoming symlinks, with the real full folder authorized.
        incoming=root/'data/incoming'; incoming.mkdir(parents=True)
        for video in videos[:3]: (incoming/video.name).symlink_to(video)
        call('media.library.roots.add',{'paths':[str(incoming)]})
        wait_job(call('media.library.scan',{'root':str(incoming),'requestId':profile+'-incoming'})['job'])
        record('before-agent-files',query('library.files'))
        prompt='《长安十二时辰》放进来了，帮我整理一下，弄好看点。'
        record('user-prompt',prompt)
        started=time.monotonic(); record('turn',vm.chat('turn',text=prompt))
        deadline=started+900; previous=None
        while time.monotonic()<deadline:
            status=vm.chat('status')['liveness']
            if status['status']!=previous: record('liveness',status); previous=status['status']
            if previous not in ('starting','inProgress'): break
            time.sleep(1)
        else: record('watchdog-interrupt',vm.chat('interrupt'))
        record('turn-seconds',time.monotonic()-started)
        header=vm.chat('status')['header']; record('agent-thread',vm.chat('read',threadId=header['threadId']))
        query('library.files'); query('danmaku.bindings')
        call('task.list',{'type':'agent.helper'})
        for w in query('library.works'): call('media.metadata.ui_facts',{'workId':w['workId']})
        record('ui-home',vm.rpc('ext.nipaplay.uiData',isolateId=vm.isolate,op='home'))
        capture('result')
finally:
    if app is not None and app.poll() is None:
        if vm:
            try: vm.chat('close')
            except (RuntimeError,OSError): pass
        app.terminate(); app.wait(timeout=30)
    if (root/'chat-events.jsonl').exists():
        text=(root/'chat-events.jsonl').read_text()
        with gzip.open(evidence/'chat-events.jsonl.gz','wt') as out: out.write(clean(text))
    # Body errors retain observations; no profile is retained or reused accidentally.
    shutil.rmtree(root)
    record('cleanup',{'pid':app.pid if app else None,'profileRemoved':not root.exists()})
