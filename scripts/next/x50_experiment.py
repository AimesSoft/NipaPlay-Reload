#!/usr/bin/env python3
"""X50: isolated real-model A/B, fresh CODEX_HOME, quiet owned process cleanup."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import urllib.parse
import urllib.request

from x23_vm import LabVM

WORKSPACE = Path(__file__).resolve().parents[2]
EVIDENCE = WORKSPACE / 'docs/next/evidence/x50'
PROFILES = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles'
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
CLI = __import__('runpy').run_path(str(WORKSPACE / 'assets/next/harness/nipa'))
REDACT = CLI['redact']
SAFETY = '''\n## 实验范围\n这是可删除的隔离实验，只操作当前 harness 和连接的实例。不读取用户的浏览器、钥匙串、真实应用数据或其他 harness。不查找、启动其他应用，不激活窗口、不点击。工具与文件写在当前 harness，临时目录用环境中的 TMPDIR。没有授权下载、播放、删除或订阅；公开资料查询和用户明确要求的资料修改、只读弹幕检查已授权。\n'''
PROMPTS = {
    'metadata': '好，把《莉可丽丝：友谊是时间的窃贼》的中文简介补上吧。',
    'helper': '派个帮手去把《莉可丽丝：友谊是时间的窃贼》每一集的弹幕情况查一遍（每集有没有、多少条），查完告诉我。你这边先别等它。',
    'trust': '不调用任何工具，告诉我本次实验种子代号和会话 hook 给出的代号。',
}


def prepare_config(home, root):
    # Copy only provider settings/auth, never user's projects, plugins, hooks or notify.
    original = (Path.home() / '.codex/config.toml').read_text()
    provider = re.search(r'(?m)^model_provider\s*=\s*"([^"]+)"', original)[1]
    block = re.search(r'(?ms)^\[model_providers\.' + re.escape(provider) + r'\]\n(.*?)(?=^\[|\Z)', original)[1]
    config = ('model = "deepseek-v4.1-flash"\nmodel_provider = ' + json.dumps(provider) +
              '\nmodel_reasoning_effort = "high"\n[features]\nmulti_agent = true\n' +
              '[model_providers.' + provider + ']\n' + block)
    (home / 'config.toml').write_text(config)
    (home / 'config.toml').chmod(0o600)
    shutil.copy2(Path.home() / '.codex/auth.json', home / 'auth.json')
    shutil.copy2('/etc/ssl/cert.pem', root / 'system-ca.pem')
    hosts = ['127.0.0.1', 'localhost'] + [urllib.parse.urlparse(u).hostname for u in
        re.findall(r'(?m)^base_url\s*=\s*"([^"]+)"', config)]
    env = dict(os.environ, NIPAPLAY_PROFILE=root.name, CODEX_HOME=str(home),
        CODEX_CA_CERTIFICATE=str(root / 'system-ca.pem'), SSL_CERT_FILE=str(root / 'system-ca.pem'),
        NO_PROXY=','.join(hosts), no_proxy=','.join(hosts))
    env.pop('NIPAPLAY_LAB_QUIET', None)
    secrets = []
    def collect(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if isinstance(item, str) and re.search('token|secret|api_key|password', key, re.I):
                    secrets.append(item)
                else:
                    collect(item)
        elif isinstance(value, list):
            for item in value:
                collect(item)
    collect(json.loads((home / 'auth.json').read_text()))
    secrets += re.findall(r'(?im)^\s*[a-z_]*(?:token|secret|api_key|password)[a-z_]*\s*=\s*"([^"]+)"', config)
    return env, secrets


def run(version, task, repeat, deadline_seconds=600):
    label = f'{task}-{version}-{repeat}'
    out = EVIDENCE / label
    out.mkdir(parents=True, exist_ok=True)
    root = PROFILES / f'x50-{label}-{os.getpid()}'
    assert not root.exists()
    root.mkdir(mode=0o700)
    home = root / 'codex-home'
    home.mkdir(mode=0o700)
    app = vm = None
    result = {'version': version, 'task': task, 'repeat': repeat, 'prompt': PROMPTS[task]}
    operations = []
    try:
        env, secrets = prepare_config(home, root)
        before_config = (home / 'config.toml').read_bytes()
        harness = root / 'harness'
        shutil.copytree(WORKSPACE / 'assets/next/harness', harness)
        seed = ((EVIDENCE / 'old-seed.md') if version == 'old' else
                WORKSPACE / 'assets/next/harness/AGENTS.md').read_text()
        (harness / 'AGENTS.md').write_text(seed + SAFETY +
            ('\n本次实验种子代号：X50_AGENTS_SEEN_719。\n' if task == 'trust' else ''))
        result['seedBytes'] = len(seed.encode())
        result['seedSha256'] = hashlib.sha256(seed.encode()).hexdigest()
        result['injectedBytes'] = (harness / 'AGENTS.md').stat().st_size
        (harness / 'nipa').chmod(0o755)
        subprocess.run(['git', 'init', '--quiet', '--template=', '--initial-branch=main'], cwd=harness, check=True)
        if task == 'trust':
            hook = harness / 'hooks/x50-session.py'
            hook.write_text('import json\nfrom pathlib import Path\n'
                'Path("records").mkdir(exist_ok=True)\n'
                'Path("records/hook-ran").write_text("X50_HOOK_SEEN_937")\n'
                'print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart",'
                '"additionalContext":"会话 hook 代号：X50_HOOK_SEEN_937"}}))\n')
            (harness / '.codex/hooks.json').write_text(json.dumps({'hooks': {'SessionStart': [
                {'hooks': [{'type': 'command', 'command': 'python3 hooks/x50-session.py'}]}]}}))
        (root / 'preferences.json').write_text(json.dumps({
            'flutter.labs_enable_agent_endpoint': True,
            'flutter.labs_use_next_interface': True,
            'flutter.next_harness_path': str(harness),
            'flutter.auto_sync_enabled': False,
            'flutter.downloader_enabled': False,
            'flutter.player_volume': 0.0,
            'flutter.danmaku_auto_load_strategy': 'local',
            'flutter.skip_danmaku_matching': True,
        }))
        log = root / 'app.log'
        with log.open('w') as stream:
            app = subprocess.Popen([str(WORKSPACE / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
                cwd=WORKSPACE, env=env, stdout=stream, stderr=subprocess.STDOUT)
        expires = time.monotonic() + 150
        while time.monotonic() < expires:
            assert app.poll() is None, 'owned app exited'
            try:
                connection = json.loads((root / 'endpoint.json').read_text())
                vm = LabVM(log)
                header = vm.chat('status')['header']
                if header.get('model'):
                    break
            except (OSError, RuntimeError):
                pass
            time.sleep(.5)
        else:
            raise RuntimeError('startup deadline')
        secrets.append(connection['token'])
        assert vm.rpc('getVM')['pid'] == app.pid
        assert header['model'] == 'deepseek-v4.1-flash', header['model']
        result['header'] = header
        def call(action, inputs):
            request = urllib.request.Request(connection['url'], data=json.dumps({
                'operation': 'call', 'action': action, 'input': inputs}).encode(),
                headers={'Content-Type': 'application/json', 'Authorization': 'Bearer ' + connection['token']})
            with OPENER.open(request, timeout=120) as response:
                value = json.load(response)
            operations.append({'action': action, 'input': inputs, 'result': value})
            assert value['status'] == 'completed', REDACT(value, secrets)
            return value['result']
        if task == 'trust':
            memory = harness / 'memory'
            memory.mkdir()
            (memory / 'preferences.md').write_text('实验偏好\n')
            (memory / 'MEMORY.md').write_text('实验索引\n')
            cli_env = dict(env, NIPAPLAY_ENDPOINT_FILE=str(root / 'endpoint.json'))
            cli_results = {}
            for arguments in (['status'], ['list', '--full'], ['describe', 'download'],
                              ['describe', 'danmaku'], ['describe', 'mesh'],
                              ['call', 'download.add', '{}'], ['describe', 'wrong.action'],
                              ['query', 'missing.view', '{}'], ['call', 'state.describe', '{}']):
                process = subprocess.run(['python3', str(harness / 'nipa'), *arguments],
                    cwd=harness, env=cli_env, text=True, capture_output=True)
                value = json.loads(process.stdout)
                item = {'exitCode': process.returncode, 'terminalBytes': len(process.stdout.encode()), 'output': value}
                if value.get('outputStored'):
                    item['recordBytes'] = Path(value['file']).stat().st_size
                    item['recordPermission'] = oct(Path(value['file']).stat().st_mode & 0o777)
                    item['recordMatchesSize'] = item['recordBytes'] == value['bytes']
                cli_results[' '.join(arguments)] = item
            (out / 'cli.json').write_text(json.dumps(REDACT(cli_results, secrets), ensure_ascii=False, indent=2))
        if task != 'trust':
            ref = {'provider': 'bangumi', 'objectType': 'subject', 'externalId': '504950', 'scope': ''}
            bound = call('media.identity.bind_batch', {'requestId': label + '-fixture', 'entries': [
                {'kind': 'release', 'workRef': ref, 'reason': 'X50 isolated public catalogue fixture, verified Bangumi 504950'}]})
            work_id = bound['entries'][0]['workId']
            result['fixture'] = {'workId': work_id, 'basis': 'Live verified Bangumi 504950 catalogue; no user data or video files.'}
            request = urllib.request.Request('https://api.bgm.tv/v0/episodes?subject_id=504950&type=0&limit=100',
                headers={'User-Agent': 'NipaPlay-X50-research'})
            with OPENER.open(request, timeout=60) as response:
                episodes = json.load(response)['data']
            assert len(episodes) == 6, 'expected six verified public episodes'
            episode_bindings = call('media.identity.bind_batch', {'requestId': label + '-episodes', 'entries': [
                {'kind': 'episode', 'workRef': ref, 'episodeRefs': [
                    {'provider': 'bangumi', 'objectType': 'episode', 'externalId': str(ep['id']), 'scope': 'subject/504950'}],
                 'reason': 'X50 fixture: verified live Bangumi catalogue episode'} for ep in episodes]})
            if task == 'helper':
                authored = harness / 'records/x50-authored-comments.json'
                authored.parent.mkdir(exist_ok=True)
                for index, count in ((0, 2), (2, 3)):
                    authored.write_text(json.dumps([{'sourceTimeMs': i * 1000, 'text': 'X50 作者原创检查弹幕',
                        'mode': 1, 'colorRgb': 16777215} for i in range(count)], ensure_ascii=False))
                    call('danmaku.import', {'entityId': episode_bindings['entries'][index]['episodeIds'][0],
                        'filePath': str(authored), 'platform': 'x50-fixture', 'platformVideoId': str(index + 1),
                        'note': 'Operator-authored fixture comments, not acquired from a platform.'})
                authored.unlink()
                result['fixture']['expectedDanmakuCounts'] = [2, 0, 3, 0, 0, 0]
            # Live catalogue, operator-labelled tracks; no user videos/data.
            result['before'] = call('media.metadata.ui_facts', {'workId': work_id})
            if task == 'metadata':
                call('media.metadata.override', {'entityId': work_id, 'field': 'overview',
                    'value': 'Six short stories following the daily lives of Chisato and Takina.', 'language': 'en'})
                result['before'] = call('media.metadata.ui_facts', {'workId': work_id})
        offset = (root / 'chat-events.jsonl').stat().st_size
        started = time.monotonic()
        vm.chat('turn', text=PROMPTS[task])
        finished = False
        expires = started + deadline_seconds
        while time.monotonic() < expires:
            state = vm.chat('status')
            busy = any(t['status'] in ('inProgress', 'starting') for t in state['threads'].values())
            if not busy:
                if task == 'helper':
                    jobs = call('task.list', {'type': 'agent.helper'})['jobs']
                    if any(j['state'] not in ('succeeded', 'failed', 'cancelled') for j in jobs):
                        time.sleep(1)
                        continue
                    followups = call('followup.list', {})
                    if any(f.get('state') in ('ready', 'dispatching') or
                           f.get('deliveryState') in ('pending', 'delivering')
                           for f in followups.get('followups', [])):
                        time.sleep(1)
                        continue
                finished = True
                break
            time.sleep(1)
        result['seconds'] = round(time.monotonic() - started, 3)
        result['naturalEnd'] = finished
        result['finalState'] = vm.chat('status')
        if not finished:
            for thread_id, state in result['finalState']['threads'].items():
                if state['status'] in ('inProgress', 'starting'):
                    vm.chat('interrupt', threadId=thread_id)
        events_file = root / 'chat-events.jsonl'
        with events_file.open('rb') as stream:
            stream.seek(offset)
            raw_events = stream.read().decode()
        events = [json.loads(line)['m'] for line in raw_events.splitlines()]
        usage = {}
        model_responses = 0
        # Host redaction hides tokenUsage by name. Read only numeric accounting
        # from this disposable CODEX_HOME's rollouts, never user sessions.
        for rollout in (home / 'sessions').rglob('*.jsonl'):
            thread_id = rollout.stem
            for line in rollout.read_text().splitlines():
                item = json.loads(line)
                payload = item.get('payload', {})
                if item.get('type') == 'event_msg' and payload.get('type') == 'token_count' and payload.get('info'):
                    raw = payload['info']['total_token_usage']
                    usage[thread_id] = {re.sub(r'_([a-z])', lambda m: m[1].upper(), k): v for k, v in raw.items()}
                    model_responses += 1
        result['usageByThread'] = usage
        result['usage'] = {key: sum(u[key] for u in usage.values()) for key in
            ('inputTokens', 'cachedInputTokens', 'outputTokens', 'reasoningOutputTokens', 'totalTokens')}
        result['cacheHitRate'] = (result['usage']['cachedInputTokens'] / result['usage']['inputTokens']
                                  if result['usage']['inputTokens'] else None)
        result['turns'] = len([e for e in events if e.get('method') == 'turn/completed'])
        result['modelResponses'] = model_responses
        result['thread'] = vm.chat('read', threadId=header['threadId'])
        if task == 'trust':
            result['hookRan'] = (harness / 'records/hook-ran').exists()
            result['hookConfig'] = json.loads((harness / '.codex/hooks.json').read_text())
            result['complete'] = result['hookRan'] and all(x in json.dumps(result['thread']) for x in
                ('X50_AGENTS_SEEN_719', 'X50_HOOK_SEEN_937'))
        elif task == 'metadata':
            result['after'] = call('media.metadata.ui_facts', {'workId': work_id})
            result['complete'] = None  # Human-scored against the actual ui_facts and trace.
        else:
            result['helpers'] = call('task.list', {'type': 'agent.helper'})
            result['complete'] = None
        safe = REDACT({'events': events, 'operations': operations, 'result': result}, secrets)
        safe['result']['usage'] = result['usage']
        safe['result']['usageByThread'] = result['usageByThread']
        safe_text = json.dumps(safe, ensure_ascii=False)
        safe_text = re.sub(r'(?:http|ws)://127\.0\.0\.1:\d+/[A-Za-z0-9_-]+=', '[REDACTED VM URL]', safe_text)
        assert not any(s and s in safe_text for s in secrets)
        with gzip.open(out / 'trace.json.gz', 'wt') as stream:
            stream.write(safe_text)
        safe_result = REDACT(result, secrets)
        safe_result['usage'] = result['usage']
        safe_result['usageByThread'] = result['usageByThread']
        (out / 'metrics.json').write_text(json.dumps(safe_result, ensure_ascii=False, indent=2))
        result['codexConfigUnchanged'] = (home / 'config.toml').read_bytes() == before_config
        result['codexConfigHasProjectTrust'] = bool(re.search(r'(?m)^\[projects', (home / 'config.toml').read_text()))
        # Verify Codex's injected initial project instructions, without retaining provider requests.
        result['agentsInRollout'] = any('NipaPlay Harness' in f.read_text(errors='replace')
            for f in (home / 'sessions').rglob('*.jsonl'))
        summary = REDACT({k: v for k, v in result.items()
            if k not in ('thread', 'before', 'after', 'helpers')}, secrets)
        summary['usage'] = result['usage']
        summary['usageByThread'] = result['usageByThread']
        (out / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2))
        print(label, json.dumps({k: result[k] for k in ('naturalEnd', 'seconds', 'turns', 'usage', 'cacheHitRate', 'codexConfigUnchanged')}, ensure_ascii=False), flush=True)
    finally:
        if app is not None and app.poll() is None:
            if vm is not None:
                try:
                    vm.chat('close')
                except (OSError, RuntimeError):
                    pass
            app.terminate()
            app.wait(timeout=30)
        shutil.rmtree(root)
        (out / 'cleanup.json').write_text(json.dumps({'pid': app.pid if app else None,
            'exited': app is None or app.poll() is not None, 'profileDeleted': not root.exists()}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--task', choices=PROMPTS, required=True)
    parser.add_argument('--version', choices=['old', 'new'], default='new')
    parser.add_argument('--repeat', type=int, default=1)
    parser.add_argument('--deadline', type=int, default=600)
    args = parser.parse_args()
    run(args.version, args.task, args.repeat, args.deadline)
