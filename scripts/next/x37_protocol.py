#!/usr/bin/env python3
"""Probe Codex's real stdio protocol with an inert loopback provider."""
import json
import os
from pathlib import Path
import queue
import shutil
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

evidence = Path(__file__).resolve().parents[2] / 'docs/next/evidence/x37'
evidence.mkdir(parents=True, exist_ok=True)
rows = []
requests = []
release = threading.Event()

def record(direction, message):
    rows.append({'at': time.time(), 'direction': direction, 'message': message})

class Provider(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        requests.append({'at': time.time(), 'model': data['model']})
        release.wait(45)
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        response = {'id': 'resp_probe', 'object': 'response', 'status': 'completed',
                    'model': 'probe', 'output': []}
        try:
            self.wfile.write(('event: response.completed\ndata: ' + json.dumps(
                {'type': 'response.completed', 'response': response}) + '\n\n').encode())
        except BrokenPipeError:
            pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
threading.Thread(target=server.serve_forever, daemon=True).start()
root = Path(tempfile.mkdtemp(prefix='x37-protocol-'))
(root / 'config.toml').write_text('model="probe"\nmodel_provider="probe"\n'
    '[model_providers.probe]\nname="probe"\nwire_api="responses"\n'
    'base_url="http://127.0.0.1:%d/v1"\n' % server.server_port)
env = dict(os.environ, CODEX_HOME=str(root), NO_PROXY='127.0.0.1,localhost')
process = subprocess.Popen(['codex', 'app-server'], cwd=root, env=env,
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
responses = queue.Queue()
def read():
    for line in process.stdout:
        message = json.loads(line)
        record('received', message)
        if 'id' in message:
            responses.put(message)
threading.Thread(target=read, daemon=True).start()
counter = 0
def rpc(method, params):
    global counter
    counter += 1
    message = {'id': counter, 'method': method, 'params': params}
    record('sent', message)
    process.stdin.write(json.dumps(message) + '\n')
    process.stdin.flush()
    response = responses.get(timeout=20)
    assert response['id'] == counter, response
    return response
try:
    rpc('initialize', {'clientInfo': {'name': 'x37', 'version': '1'}})
    process.stdin.write('{"method":"initialized","params":{}}\n')
    process.stdin.flush()
    common = {'cwd': str(root), 'sandbox': 'danger-full-access', 'approvalPolicy': 'never'}
    a = rpc('thread/start', common)['result']['thread']['id']
    b = rpc('thread/start', common)['result']['thread']['id']
    ta = rpc('turn/start', {'threadId': a, 'input': [{'type': 'text', 'text': 'A hold'}]})
    tb = rpc('turn/start', {'threadId': b, 'input': [{'type': 'text', 'text': 'B hold'}]})
    deadline = time.monotonic() + 10
    while len(requests) < 2 and time.monotonic() < deadline:
        time.sleep(.1)
    rpc('turn/steer', {'threadId': a, 'expectedTurnId': ta['result']['turn']['id'],
                      'input': [{'type': 'text', 'text': 'A steering only'}]})
    rpc('turn/interrupt', {'threadId': a, 'turnId': ta['result']['turn']['id']})
    rpc('turn/steer', {'threadId': b, 'expectedTurnId': tb['result']['turn']['id'],
                      'input': [{'type': 'text', 'text': 'B steering only'}]})
    rpc('turn/steer', {'threadId': b, 'expectedTurnId': ta['result']['turn']['id'],
                      'input': [{'type': 'text', 'text': 'wrong turn'}]})
    rpc('turn/interrupt', {'threadId': b, 'turnId': tb['result']['turn']['id']})
    time.sleep(.2)
    summary = {'pid': process.pid, 'threads': [a, b], 'requestsBeforeRelease': len(requests),
               'providerRequests': requests}
    (evidence / 'protocol-summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary))
finally:
    release.set()
    process.terminate()
    process.wait(timeout=10)
    server.shutdown()
    shutil.rmtree(root)
    (evidence / 'protocol.jsonl').write_text(''.join(json.dumps(r, ensure_ascii=False) + '\n' for r in rows))
