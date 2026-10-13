#!/usr/bin/env python3
"""Operator-only enrollment; run by the controller after starting its Mac lab.

Uses the existing Mac accounts.login service/router/client, then sends only the
test token to the two isolated headless vaults over SSH stdin. Starts no remote
node and never copies model credentials. Never logs login responses or secrets.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--profile', required=True)
parser.add_argument('--worktree', type=Path, required=True)
parser.add_argument('--testservers', type=Path, default=Path('/tmp/nipa-next/testservers.json'))
parser.add_argument('--windows-data', default='D:\\nipaplay-next\\x45-lab-data')
parser.add_argument('--wsl-data', default='/home/labuser/nipaplay-next/x45-lab-data')
args = parser.parse_args()
assert args.profile.startswith('x45-') and '/' not in args.profile and '\\' not in args.profile
assert (args.worktree/'docs/next/TEAM.md').is_file()
profile = Path.home()/'Library/Application Support/NipaPlay/LabProfiles'/args.profile
endpoint = json.loads((profile/'endpoint.json').read_text())
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
def call(action, inputs):
    request = urllib.request.Request(endpoint['url'], data=json.dumps({'operation':'call','action':action,'input':inputs}).encode(),
        headers={'Content-Type':'application/json','Authorization':'Bearer '+endpoint['token']})
    with opener.open(request, timeout=60) as response: result=json.load(response)
    if result['status'] != 'completed': raise RuntimeError('operator action did not complete: '+action)
    return result['result']
account = json.loads(args.testservers.read_text())['dandanplay']
submitted = call('accounts.login', {'provider':'dandanplay','username':account['username'],'password':account['password']})
account = None
deadline = time.monotonic()+120
while time.monotonic()<deadline:
    job = call('task.get', {'jobId':submitted['jobId']})['job']
    if job['state'] in ('succeeded','failed','cancelled'):
        if job['state']!='succeeded': raise RuntimeError('test account login failed; inspect redacted task state')
        break
    time.sleep(.5)
else: raise RuntimeError('test account login observation deadline')
token = json.loads((profile/'credential-vault.json').read_text())['11:preferencesdandanplay_token']
assert token and len(token)<=4096
# The called binaries implement permissions and the private vault format.
for command in [
    ['ssh','-o','BatchMode=yes','-o','ConnectTimeout=15','workstation-wsl',
      'D:\\nipaplay-next\\x45-headless\\build\\headless\\nipaplay-headless.exe','--data',args.windows_data,'--enroll-token-stdin'],
    ['ssh','-o','BatchMode=yes','-o','ConnectTimeout=15','workstation-wsl','wsl.exe','--',
      '/home/labuser/nipaplay-next/x45-headless/build/headless/nipaplay-headless','--data',args.wsl_data,'--enroll-token-stdin']
]:
    result = subprocess.run(command, input=token.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    if result.returncode: raise RuntimeError('isolated headless test enrollment failed (no automatic SSH retry)')
token = None
print('Test account enrolled in Mac lab and both isolated headless vaults; no remote node started.')
