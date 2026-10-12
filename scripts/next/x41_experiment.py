#!/usr/bin/env python3
"""X41: quiet disposable body and real DeepSeek observations, no shared writes."""
import gzip, json, os, re, shutil, sqlite3, subprocess, sys, time
from pathlib import Path
import urllib.parse, urllib.request
from x23_vm import LabVM

workspace = Path(__file__).resolve().parents[2]
mode = sys.argv[1]
assert mode in ('body','agent')
evidence = workspace/'docs/next/evidence/x41'/mode
evidence.mkdir(parents=True,exist_ok=True)
profile = 'x41-'+mode+'-'+str(os.getpid())
root = Path.home()/'Library/Application Support/NipaPlay/LabProfiles'/profile
assert not root.exists()
root.mkdir(mode=0o700)
home=root/'codex-home'; home.mkdir(mode=0o700)
app=vm=endpoint=None
records=[]; secrets=[]
opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
def clean(v):
    if isinstance(v,str):
        for s in secrets: v=v.replace(s,'[REDACTED]')
        v=re.sub(r'(?:http|ws)://(?:127\.0\.0\.1|localhost):\d+/[A-Za-z0-9_-]+=(?:/[^\s"<>]*)?', '[REDACTED VM URL]', v)
        return re.sub(r'https?://[^\s"<>]+',lambda m: '[REDACTED URL]' if re.search(r'passkey|token=|authkey|cookie=|signature=',m[0],re.I) else m[0],v)
    if isinstance(v,dict): return {k:clean(x) for k,x in v.items()}
    if isinstance(v,list): return [clean(x) for x in v]
    return v
def record(label,value):
    records.append({'at':time.time(),'label':label,'value':clean(value)})
    (evidence/'operations.json').write_text(json.dumps(records,ensure_ascii=False,indent=2))
    print(label,flush=True)
    return value
def call(action,inputs,save=True):
    req=urllib.request.Request(endpoint['url'],data=json.dumps({'operation':'call','action':action,'input':inputs}).encode(),
        headers={'Content-Type':'application/json','Authorization':'Bearer '+endpoint['token']})
    started=time.monotonic()
    with opener.open(req,timeout=240) as response: v=json.load(response)
    if save:record(action,{'input':inputs,'seconds':time.monotonic()-started,**v})
    if v['status']!='completed':raise RuntimeError(action+': '+json.dumps(clean(v),ensure_ascii=False))
    return v['result']
def start():
    global app,vm,endpoint
    (root/'endpoint.json').unlink(missing_ok=True)
    log=root/('app-'+str(len(records))+'.log')
    with log.open('w') as stream:
        app=subprocess.Popen([str(workspace/'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
            cwd=workspace,env=env,stdout=stream,stderr=subprocess.STDOUT)
    deadline=time.monotonic()+150
    while time.monotonic()<deadline:
        assert app.poll() is None,'owned app exited'
        try:
            endpoint=json.loads((root/'endpoint.json').read_text())
            vm=LabVM(log)
            if vm.chat('status')['header'].get('model'):break
        except (OSError,RuntimeError):pass
        time.sleep(.3)
    else:raise RuntimeError('startup observation deadline')
    secrets.append(endpoint['token'])
    record('instance',call('app.instance',{},save=False))
    assert vm.rpc('getVM')['pid']==app.pid
    record('chat-header',vm.chat('status')['header'])
def stop():
    global app
    if app and app.poll() is None:
        if vm:
            try:vm.chat('close')
            except (OSError,RuntimeError):pass
        app.terminate();app.wait(timeout=30)
        record('process-exit',{'pid':app.pid,'exitCode':app.returncode})
def wait_job(job):
    deadline=time.monotonic()+600
    while time.monotonic()<deadline:
        v=call('task.get',{'jobId':job['jobId']},False)['job']
        if v['state'] in ('succeeded','failed','cancelled'):
            record('job-completed',v)
            assert v['state']=='succeeded',clean(v)
            return v
        time.sleep(.5)
    raise RuntimeError('scan deadline')
def wait_facts(ids):
    deadline=time.monotonic()+240
    while time.monotonic()<deadline:
        facts=call('subtitle.tracks',{'fileIds':ids},False)['files']
        if all(f['embeddedStatus'] in ('ready','unavailable') and f.get('checkedAt') for f in facts):
            return record('subtitle-facts-ready',facts)
        time.sleep(.3)
    raise RuntimeError('subtitle indexing deadline')
def capture(name):
    v=call('ui.capture',{})
    subprocess.run(['sips','-s','format','jpeg',v['path'],'--out',str(evidence/(name+'.jpg'))],
        check=True,capture_output=True)
def play(path,wanted=None):
    call('playback.open',{'path':str(path)})
    deadline=time.monotonic()+90
    while time.monotonic()<deadline:
        v=call('playback.tracks',{},False)
        if any(t['kind']=='subtitle' and t.get('selected') and
               (wanted is None or t.get('path')==wanted) for t in v['tracks']):break
        time.sleep(.4)
    else:record('playback-load-deadline',v)
    record('loaded-playback-tracks',v)
    return v
try:
    config=(Path.home()/'.codex/config.toml').read_text()
    config=re.sub(r'(?m)^model\s*=.*$','model = "deepseek-v4.1-flash"',config,count=1)
    (home/'config.toml').write_text(config);(home/'config.toml').chmod(0o600)
    shutil.copy2(Path.home()/'.codex/auth.json',home/'auth.json')
    (home/'skills').symlink_to(Path.home()/'.codex/skills',target_is_directory=True)
    shutil.copy2('/etc/ssl/cert.pem',root/'system-ca.pem')
    def collect(v):
        if isinstance(v,dict):
            for k,x in v.items():
                if isinstance(x,str) and any(s in k.lower() for s in ['token','secret','api_key','password']):secrets.append(x)
                else:collect(x)
    collect(json.loads((home/'auth.json').read_text()))
    secrets+=re.findall(r'(?im)^\s*[a-z_]*(?:token|secret|api_key|password)[a-z_]*\s*=\s*"([^"]+)"',config)
    harness=root/'harness';shutil.copytree(workspace/'assets/next/harness',harness)
    (harness/'nipa').chmod(0o755)
    subprocess.run(['git','init','--quiet','--template=','--initial-branch=main'],cwd=harness,check=True)
    with (harness/'AGENTS.md').open('a') as stream:
        stream.write('\n## 本次实验环境\n这是隔离实验，仅当前 harness 与连接实例。/Volumes/Media 是用户授权的只读 SMB 挂载；不写、不改名、不删、不复制整部，不寻找账号、不重新挂载。不启动或查找其他应用，不访问钥匙串或真实应用数据，不激活窗口、不点击、不重启；实例保持安静。工作文件写在当前 harness。用户仅请求字幕，不下载视频、音频或其他媒体；可使用公开字幕站并遵守站点规则。\n')
    prefs={'flutter.labs_enable_agent_endpoint':True,'flutter.labs_use_next_interface':True,
        'flutter.next_harness_path':str(harness),'flutter.auto_sync_enabled':False,
        'flutter.downloader_enabled':False,'flutter.player_volume':0.0,
        'flutter.danmaku_auto_load_strategy':'local','flutter.skip_danmaku_matching':True}
    (root/'preferences.json').write_text(json.dumps(prefs))
    hosts=['127.0.0.1','localhost']+[urllib.parse.urlparse(u).hostname for u in re.findall(r'(?m)^base_url\s*=\s*"([^"]+)"',config)]
    env=dict(os.environ,NIPAPLAY_PROFILE=profile,CODEX_HOME=str(home),CODEX_CA_CERTIFICATE=str(root/'system-ca.pem'),
        SSL_CERT_FILE=str(root/'system-ca.pem'),NO_PROXY=','.join(hosts),no_proxy=','.join(hosts))
    env.pop('NIPAPLAY_LAB_QUIET',None)
    start()
    if mode=='body':
        movie=next((Path('/Volumes/Media/The Big Short (2015)')).rglob('*.mkv'))
        doctor=next((Path('/Volumes/Media/Doctor-X/Final')).rglob('*.mkv'))
        changan=sorted(p for p in Path('/Volumes/Media/长安十二时辰').rglob('*') if p.suffix.lower() in ('.mkv','.mp4'))[0]
        roots=[movie.parent,doctor.parent,changan.parent]
        call('media.library.roots.add',{'paths':[str(p) for p in roots]})
        for folder in roots[:2]:
            wait_job(call('media.library.scan',{'root':str(folder),'requestId':profile+'-'+folder.name})['job'])
        ids=[call('media.identity.get',{'path':str(p)})['identity']['id'] for p in [movie,doctor,changan]]
        facts=wait_facts(ids)
        (evidence/'discovered.json').write_text(json.dumps(clean(facts),ensure_ascii=False,indent=2))
        v=play(movie)
        assert sum(t['origin']=='sidecar' for t in facts[0]['tracks'])==5
        assert any(t['origin']=='sidecar' for t in facts[1]['tracks'])
        assert any(t['origin']=='embedded' for t in facts[2]['tracks'])
        capture('movie-sidecar')
        authored=harness/'records/x41.zh-Hans.srt';authored.parent.mkdir(exist_ok=True)
        authored.write_text('1\n00:00:00,000 --> 00:00:10,000\nX41 实验字幕：由实验者创作，用于验证保存与重播。\n')
        imported=call('subtitle.import',{'entries':[{'fileId':ids[0],'filePath':str(authored),
            'language':'zh-Hans','title':'X41 实验中文字幕','source':{'label':'X41 operator-authored persistence fixture'}}]})['entries'][0]
        assert imported['saved']
        track=imported['track'];call('subtitle.select',{'fileId':ids[0],'trackId':track['id']})
        authored.unlink()
        record('original-removed',{'sourceExists':authored.exists(),'ownedCopyExists':Path(track['path']).exists()})
        stop()
        # Explicitly labelled projection fixture in this disposable observer only.
        # No provider identity is invented; these rows exist solely to attach actual file facts to episodes.
        with sqlite3.connect(root/'data/next/next.db') as db:
            for i,(fid,title) in enumerate(zip(ids,['The Big Short (2015)','Doctor-X FINAL','长安十二时辰 第1集'])):
                wid='x41-body-work-'+str(i);rid='x41-body-release-'+str(i);eid='x41-body-episode-'+str(i)
                for ident,kind,parent,attrs in [(wid,'work',None,{'title':title}),
                    (rid,'release',wid,{'title':title,'season':1}),
                    (eid,'episode',rid,{'title':title,'number':'1','season':1})]:
                    db.execute('INSERT INTO media_entities(id,kind,parent_id,revision,attributes) VALUES(?,?,?,0,?)',
                        (ident,kind,parent,json.dumps(attrs,ensure_ascii=False)))
                db.execute('INSERT INTO media_file_episodes(file_id,episode_id,relation,ordinal) VALUES(?,?,?,0)',(fid,eid,'exact'))
        record('projection-fixture',{'onlyOwnedProfile':True,'basis':'Operator-labelled local work/episode projection for actual scanned files; no external identities declared','files':ids})
        start()
        for i in range(3):
            ui=call('media.metadata.ui_facts',{'workId':'x41-body-work-'+str(i)})
            (evidence/('ui-facts-'+str(i)+'.json')).write_text(json.dumps(clean(ui),ensure_ascii=False,indent=2))
            assert ui['episodes']['subtitles']==1
        v=play(movie,track['path'])
        assert any(t.get('path')==track['path'] and t.get('selected') for t in v['tracks'])
        capture('imported-replay')
        play(changan)
        capture('embedded-playback')
        record('persisted-facts',call('subtitle.tracks',{'fileIds':ids},False))
    else:
        source=Path('/Volumes/Media/无职转生 第二季')
        call('media.library.roots.add',{'paths':[str(source)]})
        wait_job(call('media.library.scan',{'root':str(source),'requestId':profile+'-scan'})['job'])
        files=call('state.query',{'view':'library.files','limit':200})['rows']
        wait_facts([f['fileId'] for f in files])
        prompt='《无职转生》第二季有中文字幕吗？没有的话帮我配上。'
        record('user-prompt',prompt)
        record('turn',vm.chat('turn',text=prompt))
        started=time.monotonic();deadline=started+900;previous=None
        while time.monotonic()<deadline:
            status=vm.chat('status')['liveness']
            if status['status']!=previous:record('liveness',status);previous=status['status']
            if previous not in ('starting','inProgress'):break
            time.sleep(1)
        else:record('watchdog-interrupt',vm.chat('interrupt'))
        record('turn-seconds',time.monotonic()-started)
        header=vm.chat('status')['header']
        record('agent-thread',vm.chat('read',threadId=header['threadId']))
        record('final-subtitle-facts',call('subtitle.tracks',{},False))
        for w in call('state.query',{'view':'library.works','limit':200})['rows']:
            call('media.metadata.ui_facts',{'workId':w['workId']})
        capture('result')
except Exception as error:
    record('experiment-error',{'type':type(error).__name__,'message':str(error)})
    raise
finally:
    stop()
    if (root/'chat-events.jsonl').exists():
        with gzip.open(evidence/'chat-events.jsonl.gz','wt') as out:out.write(clean((root/'chat-events.jsonl').read_text()))
    for log in root.glob('app-*.log'):
        with gzip.open(evidence/(log.name+'.gz'),'wt') as out:out.write(clean(log.read_text(errors='replace')))
    shutil.rmtree(root)
    record('cleanup',{'pid':app.pid if app else None,'profileRemoved':not root.exists()})
