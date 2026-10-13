#!/usr/bin/env python3
"""Automatic local-only integration check: mock gateway, real CA/mTLS/rqbit.

No real account, GUI, model, workstation connection or public BT endpoint.
The conversation target is a synthetic fixture; no model turn is claimed.
"""
import argparse
import base64
import datetime
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
import urllib.parse

workspace = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(workspace / 'docs/next/evidence/x44'))
from local_seed import seed
parser = argparse.ArgumentParser()
parser.add_argument('--evidence', type=Path, required=True)
parser.add_argument('--programs', action='store_true', help='X46 program/subtitle checks; no BT or model')
parser.add_argument('--subscriptions', action='store_true', help='Only the X46 manual return follow-up observation')
parser.add_argument('--scope-only', action='store_true', help='Only X53 remote facts, families and write scope')
args = parser.parse_args()
args.programs = args.programs or args.subscriptions or args.scope_only
args.evidence.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix='x46-local-' if args.programs else 'x45-local-', dir='/tmp/nipa-next')).resolve()
binary = workspace / 'build/headless/nipaplay-headless'
native = workspace / 'rust/headless/target/debug/libnipaplay_headless_native.dylib'
coordinator = workspace / 'server/nipaplay-mesh-coordinator/target/debug/nipaplay-mesh-coordinator'
env = {k: v for k, v in os.environ.items() if not k.lower().endswith('proxy') and not k.startswith('DANDANPLAY_')}
env.update(NO_PROXY='127.0.0.1,localhost,::1', no_proxy='127.0.0.1,localhost,::1')
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
processes, servers, handles, records = [], [], [], []
gates = [threading.Event() for _ in range(3)]
trace = []
def evidence_value(value):
    if isinstance(value, dict):
        return {key: ('redacted-fixture-ticket-' + hashlib.sha256(item.encode()).hexdigest()[:12]
                      if key == 'returnTicket' and isinstance(item, str) else evidence_value(item))
                for key, item in value.items()}
    if isinstance(value, list):
        return [evidence_value(item) for item in value]
    return value

def record(label, value):
    value = evidence_value(value)
    records.append({'at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'label': label, 'value': value})
    (args.evidence / 'local-loopback.json').write_text(json.dumps(records, ensure_ascii=False, indent=2))
    print(label, flush=True)
def port():
    with socket.socket() as s: s.bind(('127.0.0.1', 0)); return s.getsockname()[1]
def wait(predicate, seconds=45):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        result = predicate()
        if result: return result
        assert all(p.poll() is None for p in processes), 'owned process exited'
        time.sleep(.2)
    raise RuntimeError('local observation deadline')
def spawn(command, name, environment=env):
    log = (root / (name + '.txt')).open('w'); handles.append(log)
    child = subprocess.Popen([str(a) for a in command], cwd=workspace, env=environment, stdout=log, stderr=subprocess.STDOUT)
    processes.append(child); return child
def call(data, action, input):
    endpoint = json.loads((data / 'endpoint.json').read_text())
    request = urllib.request.Request(endpoint['url'], data=json.dumps({'operation': 'call', 'action': action, 'input': input}).encode(),
        headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + endpoint['token']})
    with opener.open(request, timeout=45) as response: envelope = json.load(response)
    assert envelope['status'] == 'completed', (action, envelope)
    return envelope['result']
def invoke(data, device, action, input): return call(data, 'mesh.invoke', {'deviceId': device, 'action': action, 'input': input})
def frame():
    random = lambda: base64.urlsafe_b64encode(os.urandom(24)).decode().rstrip('=')
    return {'jsonrpc': '2.0', 'id': random(), 'mesh': {'invocationId': random(), 'nonce': random(), 'deadline': int(time.time()*1000)+300000}}
try:
    token = '.'.join([base64.urlsafe_b64encode(v).decode().rstrip('=') for v in [b'{"alg":"EdDSA"}', b'{"UserId":424242,"testOnly":true}']]) + '.synthetic-signature'
    class Gateway(BaseHTTPRequestHandler):
        def do_GET(self):
            assert urllib.parse.urlsplit(self.path).path == '/dandanplay/api/v2/playhistory'
            assert self.headers.get('Authorization') == 'Bearer ' + token
            assert not any(self.headers.get(k) for k in ('X-AppId', 'X-Signature', 'X-Timestamp'))
            self.send_response(200); self.end_headers(); self.wfile.write(b'{"success":true}')
        def log_message(self, *args): pass
    gateway = ThreadingHTTPServer(('127.0.0.1', 0), Gateway); servers.append(gateway)
    threading.Thread(target=gateway.serve_forever, daemon=True).start()
    subprocess.run([coordinator, '--generate-dev-ca', root/'ca.pem', root/'ca.key'], env=env, check=True, capture_output=True)
    cp = port()
    cenv = dict(env, MESH_CA_CERT_FILE=str(root/'ca.pem'), MESH_CA_KEY_FILE=str(root/'ca.key'),
        MESH_DATABASE_PATH=str(root/'coordinator.db'), MESH_LISTEN_ADDR=f'127.0.0.1:{cp}',
        DANDANPLAY_GATEWAY_BASE=f'http://127.0.0.1:{gateway.server_port}/dandanplay')
    cenv.pop('MESH_ACCOUNT_CLAIM_POINTER', None)
    spawn([coordinator], 'coordinator', cenv)
    def health():
        try:
            with opener.open(f'http://127.0.0.1:{cp}/healthz', timeout=1) as response: return json.load(response)['ok']
        except OSError: return False
    wait(health)
    a, b = root/'conversation-fixture', root/'transfer-fixture'
    for directory, name in [(a, 'Local conversation fixture'), (b, 'Local transfer fixture')]:
        directory.mkdir()
        (directory/'headless.json').write_text(json.dumps({'format':1,'host':'nipaplay-headless','mediaRoots':[],'port':0}))
        mp = port()
        (directory/'mesh.json').write_text(json.dumps({'coordinator':f'http://127.0.0.1:{cp}', 'name':name,
            'port':mp,'loopbackOnly':True,'broadcastDiscovery':False,'roles':['agent'] if directory == a else ['download','library'],
            'addresses':[{'kind':'manual','host':'127.0.0.1','port':mp}]}))
        (directory/'download.json').write_text(json.dumps({'dht':False,'localDiscovery':False,'trackers':True}))
        if args.programs and directory == b:
            (directory/'program.json').write_text('{"enabled":true}')
        subprocess.run([binary, '--data',directory,'--enroll-token-stdin'], input=token.encode(), env=env, check=True, capture_output=True)
    nenv = dict(env, NIPAPLAY_MESH_DEV_CA=str(root/'ca.pem'))
    spawn([binary, '--data',a,'--native-library',native], 'conversation-fixture', nenv)
    wait(lambda: (a/'endpoint.json').exists())
    wait(lambda: (a/'mesh-identity.json').exists() and (a/'mesh-certificate.json').exists())
    aid = json.loads((a/'mesh-identity.json').read_text())['deviceId']
    config = json.loads((b/'mesh.json').read_text()); config['agentDeviceId'] = aid; (b/'mesh.json').write_text(json.dumps(config))
    spawn([binary,'--data',b,'--native-library',native], 'transfer-fixture', nenv)
    wait(lambda: (b/'mesh-certificate.json').exists())
    bid = json.loads((b/'mesh-identity.json').read_text())['deviceId']
    devices = wait(lambda: (v if len(v['devices'])==2 and all(d['online'] for d in v['devices']) else None)
        if (v := call(a,'mesh.devices',{})) else None)
    record('mutual-devices', {'a':devices,'b':call(b,'mesh.devices',{})})
    record('remote-library-and-tasks', {'roots':invoke(a,bid,'media.library.roots.list',{}),
        'files':invoke(a,bid,'media.files.list',{'root':str(b/'downloads')}), 'tasks':invoke(a,bid,'task.list',{})})
    # Fixture account's real mTLS key is read only inside this test process.
    identity = json.loads((a/'mesh-identity.json').read_text())
    ref = identity['privateKey']['credentialRef']
    private = next(json.loads(f.read_text())['secret'] for f in (a/'vault').glob('*.json') if json.loads(f.read_text())['ref'] == ref)
    key = root/'client.key'; key.write_text('-----BEGIN PRIVATE KEY-----\n'+base64.b64encode(base64.urlsafe_b64decode(private+'='*((-len(private))%4))).decode()+'\n-----END PRIVATE KEY-----\n'); key.chmod(0o600)
    certificate = root/'client.pem'; certificate.write_text(json.loads((a/'mesh-certificate.json').read_text())['certificate']['pem'])
    context = ssl.create_default_context(cafile=str(root/'ca.pem')); context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.load_cert_chain(certificate, key)
    digest = base64.urlsafe_b64decode(bid+'='*((-len(bid))%4)).hex()
    dns = f'd-{digest[:32]}.{digest[32:]}.mesh.nipaplay.invalid'
    bp = json.loads((b/'mesh.json').read_text())['port']
    def raw(method, params):
        request = {**frame(), 'method':method,'params':params}
        with socket.create_connection(('127.0.0.1',bp),timeout=15) as tcp:
            with context.wrap_socket(tcp,server_hostname=dns) as tls:
                def read(n):
                    data=b''
                    while len(data)<n:
                        block=tls.recv(n-len(data))
                        if not block: raise EOFError()
                        data+=block
                    return data
                payload=json.dumps(request).encode(); tls.sendall(struct.pack('>I',len(payload))+payload)
                response=json.loads(read(struct.unpack('>I',read(4))[0]))
        assert 'error' not in response, response
        return response['result']
    if args.scope_only:
        from program_loopback_scenario import check_scope
        check_scope(a=a, b=b, aid=aid, bid=bid, raw=raw,
                    invoke=invoke, record=record, env=env, workspace=workspace)
    elif args.subscriptions:
        from program_loopback_scenario import check_subscriptions
        check_subscriptions(root=root, a=a, b=b, aid=aid, bid=bid,
                            raw=raw, invoke=invoke, call=call, wait=wait, record=record)
    elif args.programs:
        from program_loopback_scenario import check_programs
        check_programs(root=root, a=a, b=b, aid=aid, bid=bid,
                       raw=raw, invoke=invoke, call=call, wait=wait, record=record, env=env, workspace=workspace)
    else:
        tools = raw('tools/list',{})['tools']; add = next(t for t in tools if t['_meta']['nipaplay/actionId']=='download.add')
        videos=[]
        for i in range(3):
            video=root/f'cc0-{i}.mp4'; videos.append(video)
            subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i',f'testsrc2=size=320x180:rate=12:duration={2+i}',
                '-c:v','libx264','-preset','fast','-crf','26',str(video)],check=True,capture_output=True)
        torrent=root/'collection.torrent'; servers.extend(seed(videos,torrent,'X45 local CC0',gates,trace))
        ticket='synthetic-issued-target'
        target={'threadId':'original-synthetic-thread','repository':str(a/'harness'),
            'origin':'harness_cli:chat:synthetic','invocationId':'fixture-download'}
        (a/'mesh-return-targets.json').write_text(json.dumps({ticket:{'peer':bid,**target}}))
        added=raw('tools/call',{'name':add['name'],'arguments':{'source':str(torrent)},'meshDestructive':False,
            'returnTo':{**target,'deviceId':aid,'returnTicket':ticket}})['structuredContent']
        assert added['status']=='completed',added
        jid=added['result']['job']['jobId']; gates[0].set()
        def returned():
            rows=call(a,'followup.list',{})['followups']
            return next((r for r in rows if r.get('automatic')=='meshDownload'),None)
        first=wait(returned,90)
        live=invoke(a,bid,'download.read',{'jobId':jid})
        record('first-return-observed',{'followup':first,'download':live})
        assert first['threadId']==target['threadId'] and first['sourceDeviceId']==bid
        assert first['trigger']['facts'][0]['data']['file']['verification']=='verified'
        assert live['job']['state']=='running'
        record('first-file-returned-to-original-target',{'followup':first,'download':live})
        gates[1].set(); gates[2].set()
        wait(lambda:invoke(a,bid,'task.get',{'jobId':jid})['job']['state']=='succeeded',90)
        wait(lambda:any(f['event']=='task.terminal' for row in call(a,'followup.list',{})['followups']
            for f in (row.get('trigger') or {}).get('facts',[])),45)
        record('verified-terminal-and-returns',{'download':invoke(a,bid,'download.read',{'jobId':jid}),
            'destination':call(a,'followup.list',{}),'source':call(b,'followup.list',{})})
        record('remote-hook-wake',call(b,'agent.wake',{'instruction':'夹具事件事实','facts':{'event':'fixture.tick'}}))
        wait(lambda:any((r.get('trigger') or {}).get('kind')=='agent.wake' for r in call(a,'followup.list',{})['followups']))
        record('wake-arrived-at-configured-agent-device',call(a,'followup.list',{}))
        record('scope-and-isolation',{'network':'loopback only','gateway':'synthetic account','dht':False,
            'lsd':False,'meshBroadcast':False,'torrentPrivate':True,'license':'CC0-1.0',
            'bytes':[v.stat().st_size for v in videos],'modelTurns':0,'workstationConnections':0})
finally:
    for gate in gates: gate.set()
    for data in [root/'conversation-fixture',root/'transfer-fixture']:
        if (data/'endpoint.json').exists():
            record('final-state-'+data.name, {'tasks':call(data,'task.list',{}), 'followups':call(data,'followup.list',{})})
        if (data/'running.json').exists():
            subprocess.run([binary,'--stop','--data',data],cwd=workspace,env=env,capture_output=True,timeout=15)
    for child in reversed(processes):
        if child.poll() is None:
            child.terminate()
            try: child.wait(timeout=20)
            except subprocess.TimeoutExpired: child.kill(); child.wait(timeout=10)
    for server in servers: server.shutdown(); server.server_close()
    for handle in handles: handle.close()
    # Native logs contain no credentials; endpoint/private files are not copied.
    for name in ['coordinator','conversation-fixture','transfer-fixture']:
        source=root/(name+'.txt')
        if source.exists(): shutil.copy2(source,args.evidence/source.name)
    record('cleanup',{'pids':[p.pid for p in processes],'exited':all(p.poll() is not None for p in processes)})
    shutil.rmtree(root)
    record('fixture-removed',{'removed':not root.exists()})
