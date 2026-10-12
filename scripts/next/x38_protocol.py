#!/usr/bin/env python3
"""Real Codex native collaboration against a credential-free loopback model."""
import itertools
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


class Provider(BaseHTTPRequestHandler):
    sequence = itertools.count()
    release = threading.Event()
    parent_release = threading.Event()
    tools_seen = {}
    requests_seen = []

    def log_message(self, *_):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.requests_seen.append(body)
        for namespace in body.get('tools', []):
            for tool in namespace.get('tools', [namespace]):
                self.tools_seen[tool.get('name', '')] = tool
        inputs = body.get('input', [])
        latest = max(index for index, item in enumerate(inputs) if item.get('role') == 'user')
        text = ''.join(part.get('text', '') for part in inputs[latest].get('content', []))
        calls = [item for item in inputs[latest + 1:] if item.get('type') == 'function_call']
        outputs = [item for item in inputs[latest + 1:] if item.get('type') == 'function_call_output']
        name = arguments = None
        reply = '主回合结束，不等待。'
        if 'PROBE:busy' in text:
            self.parent_release.wait(90)
        elif 'CHILD:HOLD' in text:
            self.release.wait(90)
            reply = '每集弹幕结果：第1集 17 条；第2集 0 条。'
        elif 'CHILD:FAST' in text:
            reply = '已完成只读检查，17 条。'
        elif 'CHILD:SECOND' in text:
            reply = '第二次只读检查，23 条。'
        elif 'PROBE:spawn' in text and not outputs:
            fast = 'spawn-fast' in text or 'spawn-reuse' in text or 'spawn-wait' in text and 'timeout' not in text
            name, arguments = 'spawn_agent', {'message': 'CHILD:FAST' if fast else 'CHILD:HOLD', 'agent_type': 'default'}
        elif 'PROBE:spawn-wait' in text and len(outputs) == 1:
            child = json.loads(outputs[0]['output'])['agent_id']
            name, arguments = 'wait_agent', {'targets': [child], 'timeout_ms': 10000}
        elif 'PROBE:spawn-reuse' in text and len(outputs) == 1:
            child = json.loads(outputs[0]['output'])['agent_id']
            name, arguments = 'send_input', {'target': child, 'message': 'CHILD:SECOND'}
        elif 'PROBE:wait' in text and not outputs:
            name, arguments = 'wait_agent', {'targets': [text.split('PROBE:wait ', 1)[1].strip()], 'timeout_ms': 10000}
        elif 'PROBE:send' in text and not outputs:
            name, arguments = 'send_input', {'target': text.split('PROBE:send ', 1)[1].strip(), 'message': 'CHILD:FAST'}
        elif 'PROBE:second' in text and not outputs:
            name, arguments = 'send_input', {'target': text.split('PROBE:second ', 1)[1].strip(), 'message': 'CHILD:SECOND'}
        elif 'PROBE:close' in text and not outputs:
            name, arguments = 'close_agent', {'target': text.split('PROBE:close ', 1)[1].strip()}
        elif 'PROBE:resume' in text and not outputs:
            name, arguments = 'resume_agent', {'id': text.split('PROBE:resume ', 1)[1].strip()}
        elif '[NipaPlay followup' in text:
            reply = '收到后台帮手的结果，已向用户交回。'
        sequence = next(self.sequence)
        if name:
            item = {'id': f'fc_{sequence}', 'type': 'function_call', 'status': 'completed',
                    'call_id': f'call_{sequence}', 'name': name, 'namespace': 'multi_agent_v1', 'arguments': json.dumps(arguments)}
        else:
            item = {'id': f'msg_{sequence}', 'type': 'message', 'role': 'assistant', 'status': 'completed',
                    'content': [{'type': 'output_text', 'text': reply, 'annotations': []}]}
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()

        def send(event):
            self.wfile.write(('event: ' + event['type'] + '\ndata: ' + json.dumps(event) + '\n\n').encode())
            self.wfile.flush()

        base = {'id': f'resp_{sequence}', 'object': 'response', 'model': 'probe',
                'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2}}
        try:
            send({'type': 'response.created', 'response': dict(base, status='in_progress', output=[])})
            send({'type': 'response.output_item.added', 'output_index': 0,
                  'item': dict(item, arguments='') if name else dict(item, content=[])})
            send({'type': 'response.output_item.done', 'output_index': 0, 'item': item})
            send({'type': 'response.completed', 'response': dict(base, status='completed', output=[item])})
        except (BrokenPipeError, ConnectionResetError):
            pass


def main():
    evidence = Path(__file__).resolve().parents[2] / 'docs/next/evidence/x38'
    evidence.mkdir(parents=True, exist_ok=True)
    rows = []
    server = ThreadingHTTPServer(('127.0.0.1', 0), Provider)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    root = Path(tempfile.mkdtemp(prefix='x38-protocol-'))
    (root / 'config.toml').write_text('model="probe"\nmodel_provider="probe"\n'
        '[features]\nmulti_agent=true\n[model_providers.probe]\nname="probe"\nwire_api="responses"\n'
        'base_url="http://127.0.0.1:%d/v1"\n' % server.server_port)
    process = subprocess.Popen(['codex', 'app-server'], cwd=root,
        env=dict(os.environ, CODEX_HOME=str(root), NO_PROXY='127.0.0.1,localhost'),
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    responses = queue.Queue()

    def record(direction, message):
        rows.append({'at': time.time(), 'direction': direction, 'message': message})

    def read():
        for line in process.stdout:
            message = json.loads(line)
            record('received', message)
            if 'id' in message:
                responses.put(message)

    threading.Thread(target=read, daemon=True).start()
    counter = itertools.count(1)

    def rpc(method, params):
        identifier = next(counter)
        message = {'id': identifier, 'method': method, 'params': params}
        record('sent', message)
        process.stdin.write(json.dumps(message) + '\n')
        process.stdin.flush()
        response = responses.get(timeout=30)
        assert response['id'] == identifier, response
        assert 'error' not in response, response
        return response['result']

    def until(predicate):
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            value = predicate()
            if value:
                return value
            time.sleep(.05)
        raise RuntimeError('observation deadline reached')

    def turn(thread, text):
        result = rpc('turn/start', {'threadId': thread, 'input': [{'type': 'text', 'text': text}]})
        identifier = result['turn']['id']
        until(lambda: any(row['message'].get('method') == 'turn/completed' and
            row['message']['params']['turn']['id'] == identifier for row in rows))
        return identifier

    def spawned():
        return [row['message']['params']['item']['receiverThreadIds'][0] for row in rows
            if row['message'].get('method') == 'item/completed' and
            row['message']['params']['item'].get('tool') == 'spawnAgent' and
            row['message']['params']['item']['receiverThreadIds']]

    try:
        rpc('initialize', {'clientInfo': {'name': 'x38', 'version': '1'}})
        process.stdin.write('{"method":"initialized","params":{}}\n')
        process.stdin.flush()
        parent = rpc('thread/start', {'cwd': str(root), 'sandbox': 'danger-full-access',
            'approvalPolicy': 'never'})['thread']['id']
        turn(parent, 'PROBE:spawn')
        child = until(lambda: spawned() and spawned()[0])
        default_list = rpc('thread/list', {'cwd': str(root), 'modelProviders': []})
        native_list = rpc('thread/list', {'cwd': str(root), 'modelProviders': [],
            'sourceKinds': ['subAgentThreadSpawn']})
        child_turn = until(lambda: next((row['message']['params']['turn']['id'] for row in rows
            if row['message'].get('method') == 'turn/started' and
            row['message']['params']['threadId'] == child), None))
        rpc('turn/interrupt', {'threadId': child, 'turnId': child_turn})
        until(lambda: any(row['message'].get('method') == 'turn/completed' and
            row['message']['params']['turn']['id'] == child_turn for row in rows))
        turn(parent, 'PROBE:send ' + child)
        turn(parent, 'PROBE:wait ' + child)
        turn(parent, 'PROBE:close ' + child)
        turn(parent, 'PROBE:resume ' + child)
        turn(parent, 'PROBE:spawn')
        second = until(lambda: len(spawned()) > 1 and spawned()[1])
        before_release = len(rows)
        Provider.release.set()
        until(lambda: any(row['message'].get('method') == 'turn/completed' and
            row['message']['params']['threadId'] == second for row in rows[before_release:]))
        time.sleep(2)
        history = rpc('thread/read', {'threadId': parent, 'includeTurns': True})
        summary = {'version': subprocess.check_output(['codex', '--version'], text=True).strip(),
            'pid': process.pid, 'parent': parent, 'children': [child, second],
            'defaultList': default_list, 'nativeList': native_list,
            'parentEventsAfterChildRelease': [row for row in rows[before_release:]
                if row['direction'] == 'received' and row['message'].get('params', {}).get('threadId') == parent],
            'parentTurnCount': len(history['thread']['turns']),
            'childHistory': rpc('thread/read', {'threadId': second, 'includeTurns': True})}
        (evidence / 'protocol-summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
        print(json.dumps({'parent': parent, 'children': [child, second],
            'parentEventsAfterChildRelease': summary['parentEventsAfterChildRelease'],
            'collabTools': sorted({row['message'].get('params', {}).get('item', {}).get('tool')
                for row in rows if row['message'].get('params', {}).get('item', {}).get('type') == 'collabAgentToolCall'})}))
    finally:
        Provider.release.set()
        process.terminate()
        process.wait(timeout=10)
        server.shutdown()
        shutil.rmtree(root)
        (evidence / 'protocol.jsonl').write_text(''.join(json.dumps(row, ensure_ascii=False) + '\n' for row in rows))
        (evidence / 'model-tools.json').write_text(json.dumps({name: tool for name, tool in Provider.tools_seen.items()
            if name in ['spawn_agent', 'wait_agent', 'send_input', 'close_agent', 'resume_agent']}, indent=2))
        (evidence / 'model-outputs.json').write_text(json.dumps([item for body in Provider.requests_seen
            for item in body.get('input', []) if item.get('type') == 'function_call_output'], indent=2))


if __name__ == '__main__':
    main()
