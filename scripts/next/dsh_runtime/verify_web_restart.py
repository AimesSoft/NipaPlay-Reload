"""在已静音的独立 macOS 实验实例中验证首次启用 Web。

传入 run.log 与全新实验配置的绝对目录。预装基础 DSH，保留真实
Web 安装流程，不预配模型，也不预装 Web。随实验启动脚本在 lab-run 下执行。
"""

import argparse
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import subprocess
import threading
import time
from urllib.parse import urlencode
from urllib.request import ProxyHandler, build_opener


class Model(BaseHTTPRequestHandler):
    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.server.models.append(request['model'])
        chunks = [
            {'delta': {'role': 'assistant', 'content': '本地回归测试。'}, 'finish_reason': None},
            {'delta': {}, 'finish_reason': 'stop'},
        ]
        body = ''.join('data: ' + json.dumps({
            'id': 'fixture', 'object': 'chat.completion.chunk', 'created': 0,
            'model': request['model'], 'choices': [{'index': 0, **chunk}],
        }) + '\n\n' for chunk in chunks) + 'data: [DONE]\n\n'
        payload = body.encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/event-stream')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def verify(log, profile, model):
    vm = re.findall(r'Dart VM service is listening on (http://\S+)', log.read_text())[-1]
    assert vm.startswith('http://127.0.0.1:')
    client = build_opener(ProxyHandler({}))

    def rpc(method, **params):
        with client.open(vm + method + '?' + urlencode(params), timeout=90) as response:
            value = json.load(response)
        if 'error' in value:
            raise RuntimeError(value['error'])
        return value['result']

    isolate = next(row['id'] for row in rpc('getVM')['isolates'] if row['name'] == 'main')

    def ext(surface, operation, **params):
        return rpc(f'ext.nipaplay.{surface}', isolateId=isolate, op=operation, **params)

    def store(action, **params):
        return ext('nextui', 'guicall', action=f'store.{action}', input=json.dumps(params))['result']

    def dsh_pids():
        rows = subprocess.check_output(['/bin/ps', '-axo', 'pid=,command='], text=True)
        node = str(profile / 'data/next/dsh-runtime') + '/'
        return {int(row.split()[0]) for row in rows.splitlines()
                if row.strip().split(maxsplit=1)[1].startswith(node) and '/node/node ' in row}

    ext('nextui', 'interface', next='true')
    choice = json.dumps(dict(
        source='nipaplay', provider='本地回归夹具', model='restart-fixture', api='chat',
        baseUrl=f'http://127.0.0.1:{model.server_port}/v1', apiKey='local-fixture-only'))
    barrier = threading.Barrier(8)

    def save(_):
        barrier.wait(timeout=10)
        return ext('hostSettings', 'setModel', choice=choice)

    with ThreadPoolExecutor(8) as pool:
        assert all(item['saved'] for item in pool.map(save, range(8)))
    before = ext('chat', 'main')['thread']['id']
    old_pids = dsh_pids()
    assert len(old_pids) == 1, old_pids
    web = store('list')['dshWeb']
    assert not web['installed'], web
    store('install', id='dsh-web', version=web['version'])
    receipt = store('apply')
    assert receipt['restarted'], receipt
    new_pids = dsh_pids()
    assert len(new_pids) == 1 and not old_pids & new_pids, (old_pids, new_pids)
    after = ext('chat', 'main')['thread']['id']
    assert after == before
    assert ext('chat', 'dshWeb')['url']
    ext('chat', 'turn', text='检查重启后的对话。')
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if ext('chat', 'status')['liveness']['status'] == 'completed':
            break
        time.sleep(.25)
    else:
        raise AssertionError('重启后的回合没有完成')
    assert model.models == ['restart-fixture'], model.models
    print(f'首次 Web 重启成功：{old_pids} → {new_pids}，原会话可继续对话。')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    parser.add_argument('profile', type=Path)
    args = parser.parse_args()
    with ThreadingHTTPServer(('127.0.0.1', 0), Model) as model:
        model.models = []
        worker = threading.Thread(target=model.serve_forever, daemon=True)
        worker.start()
        try:
            verify(args.log, args.profile.resolve(), model)
        finally:
            model.shutdown()
            worker.join()
