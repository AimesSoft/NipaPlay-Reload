"""Finds which files a running Nipa needs from an installed DSH.

Runs DSH with NipaPlay's patch (patch.dart) against a scripted Responses
server that makes it use every tool Nipa has (bash and a background job,
read, read_image, write, web_fetch, todo_write, list_agents, a subagent) and
compact the conversation, while the trace-*.{mjs,cjs} preloads record every
module and file it loads or reads. build_lock.py turns that list into the
package set to download.

  DSH_INSTALL=<npm install dir>  DSH_NODE=<node 24>  TRACE_OUT=loaded.txt \
  TRACE_SCRIPT=<json, see run_trace.sh>  python3 trace.py

TRACE=0 runs without the recorders. Run it again against the trimmed tree
(DSH_INSTALL=<materialised lock>) to check that nothing is missing.
"""
import asyncio, json, os, re, sys, threading, time, pathlib
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

HERE = pathlib.Path(__file__).parent
REPO = HERE.parents[2]
WORK = pathlib.Path(os.environ.get('TRACE_WORK', '/tmp/nipa-next/dsh-trace'))
INSTALL = pathlib.Path(os.environ['DSH_INSTALL'])
NODE = os.environ.get('DSH_NODE', 'node')
OUT = pathlib.Path(os.environ.get('TRACE_OUT', '/tmp/nipa-next/dsh-trace/loaded.txt'))
SCRIPT = json.loads(os.environ['TRACE_SCRIPT']) if 'TRACE_SCRIPT' in os.environ else []
requests = []

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.send_header('Content-Type', 'text/html'); self.end_headers(); self.wfile.write(b'<html><body><h1>hello trace</h1><p>a page</p></body></html>')
    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        body = json.loads(raw or b'{}')
        n = len(requests); requests.append(body)
        self.send_response(200); self.send_header('Content-Type', 'text/event-stream'); self.end_headers()
        def send(t, d):
            self.wfile.write(('event: %s\ndata: %s\n\n' % (t, json.dumps({'type': t, **d}))).encode()); self.wfile.flush()
        resp = {'id': 'r%d' % n, 'object': 'response', 'created_at': int(time.time()), 'status': 'in_progress', 'model': 'm', 'output': []}
        usage = {'input_tokens': 100, 'output_tokens': 10, 'total_tokens': 110, 'input_tokens_details': {'cached_tokens': 0}, 'output_tokens_details': {'reasoning_tokens': 0}}
        step = SCRIPT[n] if n < len(SCRIPT) else None
        if step:
            text = json.dumps(step).replace('PORT', str(port))
            job = re.findall(r'bash-[0-9a-f]{16}', json.dumps(body))
            if job:
                text = text.replace('JOBID', job[-1])
            step = json.loads(text)
        send('response.created', {'response': resp})
        if step and step.get('tool'):
            names = [t.get('name') for t in body.get('tools', [])]
            if step['tool'] not in names:
                print('MISSING TOOL', step['tool'], names, flush=True)
            item = {'type': 'function_call', 'id': 'fc%d' % n, 'call_id': 'call%d' % n, 'name': step['tool'], 'arguments': json.dumps(step['args']), 'status': 'completed'}
            send('response.output_item.added', {'output_index': 0, 'item': {**item, 'arguments': '', 'status': 'in_progress'}})
            send('response.function_call_arguments.done', {'item_id': item['id'], 'output_index': 0, 'arguments': item['arguments']})
            send('response.output_item.done', {'output_index': 0, 'item': item})
            send('response.completed', {'response': {**resp, 'status': 'completed', 'output': [item], 'usage': usage}})
        else:
            text = 'done'
            item = {'type': 'message', 'id': 'm%d' % n, 'role': 'assistant', 'status': 'completed', 'content': [{'type': 'output_text', 'text': text, 'annotations': []}]}
            send('response.output_item.added', {'output_index': 0, 'item': {**item, 'content': [], 'status': 'in_progress'}})
            send('response.content_part.added', {'item_id': item['id'], 'output_index': 0, 'content_index': 0, 'part': {'type': 'output_text', 'text': '', 'annotations': []}})
            send('response.output_text.delta', {'item_id': item['id'], 'output_index': 0, 'content_index': 0, 'delta': text})
            send('response.output_text.done', {'item_id': item['id'], 'output_index': 0, 'content_index': 0, 'text': text})
            send('response.content_part.done', {'item_id': item['id'], 'output_index': 0, 'content_index': 0, 'part': item['content'][0]})
            send('response.output_item.done', {'output_index': 0, 'item': item})
            send('response.completed', {'response': {**resp, 'status': 'completed', 'output': [item], 'usage': usage}})

server = ThreadingHTTPServer(('127.0.0.1', 0), H)
port = server.server_address[1]
threading.Thread(target=server.serve_forever, daemon=True).start()

async def main():
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / 'plugins').mkdir(exist_ok=True); (WORK / 'harness').mkdir(exist_ok=True)
    for f in (REPO / 'assets/next/agent/dsh').iterdir(): (WORK / 'plugins' / f.name).write_bytes(f.read_bytes())
    work = WORK / 'cwd'; work.mkdir(exist_ok=True)
    (work / 'AGENTS.md').write_text('# test\n')
    (work / 'out.txt').unlink(missing_ok=True)
    (work / 'pic.png').write_bytes(__import__('base64').b64decode('iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAEklEQVR4nGP4z8CAFWEXHbQSACj/P8Fu7N9hAAAAAElFTkSuQmCC'))
    home = WORK / 'dsh-home'
    if home.exists(): __import__('shutil').rmtree(home)
    home.mkdir()
    if OUT.exists(): OUT.unlink()
    env = dict(os.environ, DSH_HOME=str(home), DSH_AGENTS_HOME=str(home / 'agents'), DSH_PERMISSION_MODE='danger-full-access',
               DSH_TELEMETRY_DISABLED='1', NIPAPLAY_MODEL_API_KEY='unused', DSH_TRACE_OUT=str(OUT), NIPAPLAY_CHAT='trace')
    (home / 'agents').mkdir()
    patch = WORK / 'patch.json'
    dart = os.environ.get('DART', 'dart')
    os.system('cd %s && NIPAPLAY_TRACE_URL=http://127.0.0.1:%d/v1 NIPAPLAY_TRACE_MODEL=m %s run scripts/next/dsh_runtime/patch.dart %s/plugins %s/harness %s' % (REPO, port, dart, WORK, WORK, patch))
    bin_js = INSTALL / 'node_modules/@deepseek-ai/dsh/lib/bin.js'
    args = [NODE]
    if os.environ.get('TRACE') != '0':
        args += ['--require', str(HERE / 'trace-cjs.cjs'), '--import', str(HERE / 'trace-register.mjs')]
    args += [str(bin_js), '--profile', 'sdk', '--patch', str(patch)]
    p = await asyncio.create_subprocess_exec(*args, cwd=str(work), env=env, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE, limit=1 << 24)
    msgs = []; pending = {}; nid = [0]
    async def reader():
        while True:
            line = await p.stdout.readline()
            if not line: break
            try: m = json.loads(line)
            except Exception: continue
            msgs.append(m)
            if 'id' in m and m['id'] in pending and 'method' not in m: pending[m['id']].set_result(m)
    async def errs():
        while True:
            line = await p.stderr.readline()
            if not line: break
            print('ERR', line.decode()[:300].rstrip(), flush=True)
    asyncio.create_task(reader()); asyncio.create_task(errs())
    async def rpc(method, params, timeout=25):
        nid[0] += 1; i = nid[0]; f = asyncio.get_event_loop().create_future(); pending[i] = f
        p.stdin.write((json.dumps({'id': i, 'method': method, 'params': params}) + '\n').encode()); await p.stdin.drain()
        return await asyncio.wait_for(f, timeout)
    async def wait_turn(timeout=120):
        t0 = time.time()
        while time.time() - t0 < timeout:
            if any(m.get('method') == 'turn/completed' for m in msgs):
                r = [m for m in msgs if m.get('method') == 'turn/completed'][-1]; msgs.clear(); return r
            await asyncio.sleep(.1)
        raise TimeoutError('turn')
    await rpc('initialize', {'clientInfo': {'name': 'trace', 'title': 't', 'version': '0'}, 'capabilities': {}})
    p.stdin.write(b'{"method":"initialized","params":{}}\n')
    r = await rpc('thread/start', {'cwd': str(work), 'model': 'm', 'modelProvider': 'nipaplay', 'sandbox': 'danger-full-access', 'approvalPolicy': 'never'})
    tid = r['result']['thread']['id']
    r = await rpc('turn/start', {'threadId': tid, 'input': [{'type': 'text', 'text': 'go'}]})
    c = await wait_turn(180)
    print('turn status', c['params']['turn']['status'], 'requests', len(requests), flush=True)
    # What each tool answered: a missing module shows here, not in the status.
    names = {}
    for body in requests:
        for item in body.get('input', []):
            if item.get('type') == 'function_call':
                names[item['call_id']] = item['name']
            if item.get('type') == 'function_call_output' and item['call_id'] not in names.get('_seen', ()):
                out = item['output'] if isinstance(item['output'], str) else json.dumps(item['output'])
                names.setdefault('_seen', set()).add(item['call_id'])
                print('  tool', names.get(item['call_id'], '?'), '->', out.replace('\n', ' ')[:110], flush=True)
    if os.environ.get('TRACE_TOOLS') == '1' and requests:
        print(json.dumps([t for t in requests[0].get('tools', []) if t.get('name') in (os.environ.get('TRACE_SHOW') or 'todo_write').split(',')], indent=1))
    if os.environ.get('TRACE_COMPACT') == '1':
        r = await rpc('thread/compact/start', {'threadId': tid}, 120)
        print('compact', str(r)[:200], flush=True)
        await asyncio.sleep(3)
    await rpc('shutdown', {}, 20) if False else None
    p.stdin.close()
    try: await asyncio.wait_for(p.wait(), 10)
    except Exception: p.kill()
asyncio.run(main())
