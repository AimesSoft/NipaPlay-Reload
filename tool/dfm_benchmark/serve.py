#!/usr/bin/env python3
"""Serve the marketplace Titan build and collect local iOS benchmark results."""
import argparse
import hashlib
import http.server
import json
from pathlib import Path
import re
import time
import urllib.request

PLUGIN = ('https://raw.githubusercontent.com/AimesSoft/Nipaplay-plugins/'
          'main/plugins/titan_danmaku_renderer/titan_danmaku_renderer.js')


def prepare(directory):
    plugin = urllib.request.urlopen(PLUGIN, timeout=30).read().decode()
    url = re.search(r"url: '(https://[^']+titan-bundle.js)'", plugin).group(1)
    expected = re.search(r"sha256: '([0-9a-f]{64})'", plugin).group(1)
    script = directory / 'titan-bundle.js'
    if not script.exists() or hashlib.sha256(script.read_bytes()).hexdigest() != expected:
        data = urllib.request.urlopen(url, timeout=60).read()
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError('Titan bundle checksum mismatch')
        script.write_bytes(data)
    bootstrap = plugin.split('bootstrap: String.raw`', 1)[1].rsplit('`,', 1)[0]
    (directory / 'titan-plugin.js').write_text(plugin)
    (directory / 'source.json').write_text(json.dumps({'plugin': PLUGIN, 'bundle': url, 'sha256': expected}, indent=2))
    html = '''<!doctype html><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<style>html,body,#nipa-danmaku-root{margin:0;width:100%;height:100%;overflow:hidden;background:transparent;pointer-events:none}</style>
<div id="nipa-danmaku-root"></div><script src="titan-bundle.js"></script>
<script>(async()=>{try{ BOOTSTRAP
NipaDanmakuHost.postMessage(JSON.stringify({type:'ready'}));
}catch(e){NipaDanmakuHost.postMessage(JSON.stringify({type:'error',message:String(e.stack||e)}));}})();</script>'''
    (directory / 'titan.html').write_text(html.replace('BOOTSTRAP', bootstrap))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path('/tmp/nipaplay-dfm-benchmark'))
    parser.add_argument('--renderer', choices=['dfm', 'titan'], default='dfm')
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)
    prepare(args.directory)
    (args.directory / 'config.json').write_text(json.dumps({'renderer': args.renderer}))

    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *values, **kwargs):
            super().__init__(*values, directory=str(args.directory), **kwargs)

        def do_POST(self):
            if self.path != '/result':
                self.send_error(404)
                return
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length < 65536:
                self.send_error(400, 'Expected a small JSON result with Content-Length')
                return
            data = json.loads(self.rfile.read(length))
            (args.directory / f'result-{time.time_ns()}.json').write_text(json.dumps(data, indent=2))
            print(json.dumps(data), flush=True)
            self.send_response(200)
            self.end_headers()

    print(f'Serving {args.directory} on http://127.0.0.1:{args.port}', flush=True)
    http.server.ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()


if __name__ == '__main__':
    main()
