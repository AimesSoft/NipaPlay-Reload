"""Loopback Responses fixture. Its tool calls run in the real embedded host."""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Provider(BaseHTTPRequestHandler):
    sequence = 0

    def log_message(self, *_):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        inputs = body.get('input', [])
        last = max(i for i, v in enumerate(inputs) if v.get('role') == 'user')
        text = ''.join(p.get('text', '') for p in inputs[last].get('content', []))
        called = any(v.get('type') == 'function_call_output' for v in inputs[last+1:])
        Provider.sequence += 1
        seq = Provider.sequence
        commands = {
            '第一轮': "python3 -c 'print(\"开头检查完成\"); print(\"cookie=synthetic-private-value\")'",
            '第二轮': "python3 -c 'import time; time.sleep(0.35); print(\"退出状态已收到\"); raise SystemExit(7)'",
            '第三轮': "printf '画面检查完成\\nAuthorization: Bearer synthetic-private-value\\n'",
        }
        command = next((v for k, v in commands.items() if k in text), commands['第一轮'])
        thought = '先执行这条命令，再看看结果。' if not called else '结果已经收到。'
        print(json.dumps({'model': body.get('model'), 'called': called, 'command': command if not called else None}, ensure_ascii=False), flush=True)
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()

        def send(event):
            self.wfile.write(('event: '+event['type']+'\ndata: '+json.dumps(event, ensure_ascii=False)+'\n\n').encode())
            self.wfile.flush()

        base = {'id': f'resp_x33_{seq}', 'object': 'response', 'model': 'deepseek-v4.1-flash',
                'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2}}
        reasoning = {'id': f'rs_{seq}', 'type': 'reasoning', 'summary': [{'type': 'summary_text', 'text': thought}]}
        send({'type': 'response.created', 'response': dict(base, status='in_progress', output=[])})
        send({'type': 'response.output_item.added', 'output_index': 0, 'item': dict(reasoning, summary=[])})
        send({'type': 'response.reasoning_summary_part.added', 'output_index': 0, 'item_id': reasoning['id'], 'summary_index': 0, 'part': {'type': 'summary_text', 'text': ''}})
        send({'type': 'response.reasoning_summary_text.delta', 'output_index': 0, 'item_id': reasoning['id'], 'summary_index': 0, 'delta': thought})
        send({'type': 'response.output_item.done', 'output_index': 0, 'item': reasoning})
        if not called:
            item = {'id': f'fc_{seq}', 'type': 'function_call', 'status': 'completed', 'call_id': f'call_{seq}', 'name': 'exec_command',
                    'arguments': json.dumps({'cmd': command, 'login': False})}
            send({'type': 'response.output_item.added', 'output_index': 1, 'item': dict(item, arguments='')})
        else:
            item = {'id': f'msg_{seq}', 'type': 'message', 'role': 'assistant', 'status': 'completed',
                    'content': [{'type': 'output_text', 'text': '结果收到了。', 'annotations': []}]}
            send({'type': 'response.output_item.added', 'output_index': 1, 'item': dict(item, content=[])})
            send({'type': 'response.content_part.added', 'item_id': item['id'], 'output_index': 1, 'content_index': 0,
                  'part': {'type': 'output_text', 'text': '', 'annotations': []}})
            send({'type': 'response.output_text.delta', 'item_id': item['id'], 'output_index': 1, 'content_index': 0, 'delta': '结果收到了。'})
        send({'type': 'response.output_item.done', 'output_index': 1, 'item': item})
        send({'type': 'response.completed', 'response': dict(base, status='completed', output=[reasoning, item])})


if __name__ == '__main__':
    import sys
    ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), Provider).serve_forever()
