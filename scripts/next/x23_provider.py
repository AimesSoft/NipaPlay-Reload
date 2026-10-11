#!/usr/bin/env python3
"""A local evidence experiment: first Responses request never responds."""
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

lock = threading.Lock()
requests = 0
stopped = threading.Event()


class Provider(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        global requests
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        with lock:
            requests += 1
            number = requests
        print(json.dumps({'request': number, 'path': self.path,
                          'model': body.get('model'), 'responds': number > 1}), flush=True)
        if number == 1:
            stopped.wait()
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        text = '同一线程中断后重发成功。'
        item = {'id': 'msg_probe', 'type': 'message', 'role': 'assistant',
                'status': 'completed', 'content': [
                    {'type': 'output_text', 'text': text, 'annotations': []}]}
        response = {'id': 'resp_probe', 'object': 'response',
                    'model': 'deepseek-v4.1-flash', 'status': 'completed',
                    'output': [item], 'usage': {'input_tokens': 1, 'output_tokens': 1,
                                              'total_tokens': 2}}
        events = [
            {'type': 'response.created', 'response': dict(response, status='in_progress', output=[])},
            {'type': 'response.output_item.added', 'output_index': 0,
             'item': dict(item, status='in_progress', content=[])},
            {'type': 'response.content_part.added', 'item_id': 'msg_probe', 'output_index': 0,
             'content_index': 0, 'part': {'type': 'output_text', 'text': '', 'annotations': []}},
            {'type': 'response.output_text.delta', 'item_id': 'msg_probe', 'output_index': 0,
             'content_index': 0, 'delta': text},
            {'type': 'response.output_item.done', 'output_index': 0, 'item': item},
            {'type': 'response.completed', 'response': response},
        ]
        try:
            for event in events:
                self.wfile.write(('event: ' + event['type'] + '\ndata: ' +
                                  json.dumps(event, ensure_ascii=False) + '\n\n').encode())
                self.wfile.flush()
        except BrokenPipeError:
            print('client closed stream', flush=True)


if __name__ == '__main__':
    server = ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), Provider)
    server.daemon_threads = True
    print('mock provider listening on loopback', flush=True)
    try:
        server.serve_forever()
    finally:
        stopped.set()
        server.server_close()
