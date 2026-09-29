#!/usr/bin/env python3
"""Sample host CPU time and RSS of the iOS benchmark and optional WebKit PIDs.

100% CPU means one host core. Warm the renderer first; do not record video or
run builds during measurement. These are simulator/debug process measurements.
"""
import argparse
import json
import subprocess
import time
from pathlib import Path

from verify import Bench


def read_processes(pids):
    lines = subprocess.check_output(
        ['ps', '-p', ','.join(map(str, pids)), '-o', 'pid=,time=,rss='],
        text=True).splitlines()
    result = {}
    for line in lines:
        pid, clock, rss = line.split()
        total = 0
        for part in clock.split(':'):
            total = total * 60 + float(part)
        result[pid] = {'cpu_seconds': total, 'rss_mib': int(rss) / 1024}
    if len(result) != len(pids):
        raise RuntimeError('A selected process exited during measurement')
    return result


def measure(bench, pids, seconds, paused):
    if paused:
        bench.call(playing=False, position=10)
        time.sleep(1)
    else:
        bench.call(restart=True)
        time.sleep(8)
    before = read_processes(pids)
    start = time.monotonic()
    time.sleep(seconds)
    after = read_processes(pids)
    elapsed = time.monotonic() - start
    processes = {
        pid: {
            'cpu_percent_one_core':
                (value['cpu_seconds'] - before[pid]['cpu_seconds']) / elapsed * 100,
            'rss_mib': value['rss_mib'],
        } for pid, value in after.items()
    }
    return {
        'seconds': elapsed,
        'paused': paused,
        'processes': processes,
        'total_cpu_percent_one_core':
            sum(p['cpu_percent_one_core'] for p in processes.values()),
        'total_rss_mib': sum(p['rss_mib'] for p in processes.values()),
        'snapshot': bench.call(),
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('vm_url')
    parser.add_argument('--webkit-pids', type=int, nargs='*', default=[])
    parser.add_argument('--seconds', type=float, default=15)
    parser.add_argument('--paused', action='store_true')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not 0 < args.seconds <= 20:
        parser.error('--seconds must be in (0, 20] to remain inside the scene')
    bench = Bench(args.vm_url)
    pids = [bench.request('getVM')['pid'], *args.webkit_pids]
    data = json.dumps(measure(bench, pids, args.seconds, args.paused), indent=2)
    args.output.write_text(data + '\n')
    print(data)
