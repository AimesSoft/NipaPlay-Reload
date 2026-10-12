"""Inert Responses fixture for queue/cancel/cards; never used as DeepSeek evidence."""
import json
from http.server import BaseHTTPRequestHandler
import itertools

sequence = itertools.count(1)

class Provider(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        inputs = body.get('input', [])
        last = max(i for i, v in enumerate(inputs) if v.get('role') == 'user')
        text = ''.join(p.get('text', '') for p in inputs[last].get('content', []))
        called = any(v.get('type') == 'function_call_output' for v in inputs[last+1:])
        seq = next(sequence)
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        def send(event):
            self.wfile.write(('event: ' + event['type'] + '\ndata: ' +
                json.dumps(event, ensure_ascii=False) + '\n\n').encode())
            self.wfile.flush()
        base = {'id': f'resp_{seq}', 'object': 'response', 'model': 'deepseek-v4.1-flash',
                'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2}}
        send({'type': 'response.created', 'response': dict(base, status='in_progress', output=[])})
        if 'CONTROL:' in text and not called:
            command = text.split('CONTROL:', 1)[1].strip()
            item = {'id': f'fc_{seq}', 'type': 'function_call', 'status': 'completed',
                'call_id': f'call_{seq}', 'name': 'exec_command',
                'arguments': json.dumps({'cmd': command, 'login': False, 'yield_time_ms': 30000})}
        else:
            item = {'id': f'msg_{seq}', 'type': 'message', 'role': 'assistant', 'status': 'completed',
                'content': [{'type': 'output_text', 'text': '帮手结果已收到。', 'annotations': []}]}
        send({'type': 'response.output_item.added', 'output_index': 0,
              'item': dict(item, arguments='') if item['type'] == 'function_call' else dict(item, content=[])})
        send({'type': 'response.output_item.done', 'output_index': 0, 'item': item})
        send({'type': 'response.completed', 'response': dict(base, status='completed', output=[item])})
