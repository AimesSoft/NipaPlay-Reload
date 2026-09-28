#!/usr/bin/env python3
"""Exercise the real iOS DFM overlay through its debug VM service extension.

Run after glyph warmup. Layout assertions verify timeline synchronization;
they do not measure Metal presentation or replace visual inspection.
"""
import argparse
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path


class Bench:
    def __init__(self, url):
        self.url = url.rstrip('/') + '/'
        vm = self.request('getVM')
        self.isolate = next(i['id'] for i in vm['isolates'] if i['name'] == 'main')

    def request(self, method, **params):
        query = urllib.parse.urlencode({
            k: str(v).lower() if isinstance(v, bool) else v
            for k, v in params.items()
        })
        with urllib.request.urlopen(self.url + method + '?' + query, timeout=10) as r:
            response = json.load(r)
        if 'error' in response:
            raise RuntimeError(response['error'])
        return response['result']

    def call(self, **params):
        method = 'control' if params else 'snapshot'
        return self.request('ext.dfmBench.' + method,
                            isolateId=self.isolate, **params)

    def settled(self, expected, timeout=3):
        deadline = time.monotonic() + timeout
        while True:
            state = self.call()
            actual = state['layout'].get('sample_media')
            if actual is not None and abs(actual - expected) < .005:
                return state
            if time.monotonic() >= deadline:
                raise AssertionError(f'Expected scene time {expected}: {state}')
            time.sleep(.05)


def verify(bench):
    assert bench.call()['renderer'] == 'dfm', 'Select DFM in config.json first'
    bench.call(restart=True)
    evidence = []
    for position in [20, 8, 8.1, 8.0]:
        bench.call(playing=False, position=position, rate=1, offset=0, visible=True)
        state = bench.settled(position)
        evidence.append({'case': f'paused seek {position}', 'state': state})
    before = bench.call()['layout']
    time.sleep(1)
    assert bench.call()['layout'] == before, 'Paused scene moved'
    evidence.append({'case': 'pause stable for 1 second', 'passed': True})

    bench.call(offset=2)
    evidence.append({'case': 'offset +2 seconds', 'state': bench.settled(10)})
    bench.call(offset=0, visible=False, position=15)
    time.sleep(.2)
    bench.call(visible=True)
    evidence.append({'case': 'hidden seek then show', 'state': bench.settled(15)})

    bench.call(position=60)
    time.sleep(.3)
    assert bench.call()['layout']['count'] == 0, 'Empty segment not cleared'
    bench.call(position=5)
    evidence.append({'case': 'empty segment then back', 'state': bench.settled(5)})
    for position in [24, 2, 17, 7.05]:
        bench.call(position=position)
    evidence.append({'case': 'rapid seeks last wins', 'state': bench.settled(7.05)})

    for rate in [.5, 1, 2]:
        bench.call(playing=False, position=10, rate=rate)
        bench.settled(10)
        bench.call(playing=True)
        time.sleep(.35)
        start = bench.call()
        wall_start = time.monotonic()
        time.sleep(1.5)
        end = bench.call()
        elapsed = time.monotonic() - wall_start
        movement = end['layout']['sample_media'] - start['layout']['sample_media']
        assert abs(movement - elapsed * rate) < .25, (rate, elapsed, movement)
        assert abs(end['position'] - end['layout']['sample_media']) < .25, end
        evidence.append({'case': f'playback rate {rate}', 'wall_seconds': elapsed,
                         'scene_advance_seconds': movement})
    bench.call(playing=False, position=8, rate=1)
    bench.settled(8)
    return evidence


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('vm_url')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = verify(Bench(args.vm_url))
    data = json.dumps(result, ensure_ascii=False, indent=2)
    if args.output:
        args.output.write_text(data + '\n')
    print(data)
