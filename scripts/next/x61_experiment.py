#!/usr/bin/env python3
"""One quiet worktree Lab turn using the freshly downloaded pinned runtime.

Credentials are read only by this script and passed in memory; no raw model
responses, provider URL, VM URL or configuration are copied into evidence.
"""
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import subprocess
import threading
import time

from x52_experiment import VM, credentials


def main():
    workspace = Path(__file__).resolve().parents[2]
    app = workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay'
    download = Path('/tmp/nipa-next/x61/download')
    binary = download / '0.144.1/package/vendor/aarch64-apple-darwin/bin/codex'
    if not app.is_file() or not app.resolve().is_relative_to(workspace / 'build') or not binary.is_file():
        raise RuntimeError('Build this worktree and run the download experiment first')
    evidence = workspace / 'docs/next/evidence/x61'
    evidence.mkdir(parents=True, exist_ok=True)
    profile = 'x61-runtime-' + secrets.token_hex(5)
    root = Path.home() / 'Library/Application Support/NipaPlay/LabProfiles' / profile
    user_config = Path.home() / '.codex/config.toml'
    config_hash = hashlib.sha256(user_config.read_bytes()).hexdigest()
    address, model, key = credentials()
    wrong = 'x61-invalid-' + secrets.token_hex(20)
    private = [key.encode(), wrong.encode()]
    summary = {'profile': profile, 'runtimeVersion': '0.144.1',
               'modelSource': '自定义', 'protocol': 'Responses', 'model': model}
    process = vm = None
    owned = set()
    phase = 'prepare'

    class ChatOnly(BaseHTTPRequestHandler):
        def do_POST(self):
            self.rfile.read(int(self.headers.get('Content-Length', 0)))
            self.send_response(200 if self.path.endswith('/chat/completions') else 404)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': {'message': 'Only Chat Completions supported'}}).encode())

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), ChatOnly)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    def record_pids():
        if process is None:
            return
        pairs = [tuple(map(int, line.split())) for line in
                 subprocess.check_output(['/bin/ps', '-axo', 'pid=,ppid='], text=True).splitlines()]
        found = {process.pid}
        while True:
            extra = {pid for pid, parent in pairs if parent in found} - found
            if not extra:
                break
            found.update(extra)
        owned.update(found)

    def save():
        data = json.dumps(summary, ensure_ascii=False, indent=2).encode()
        if any(secret in data for secret in private) or address.encode() in data:
            raise RuntimeError('Evidence secret check failed')
        (evidence / 'lab.json').write_bytes(data + b'\n')

    try:
        root.mkdir(parents=True, mode=0o700)
        home = root / 'codex-home'
        home.mkdir(mode=0o700)
        harness = root / 'harness'
        (root / 'preferences.json').write_text(json.dumps({
            'flutter.labs_enable_agent_endpoint': True,
            'flutter.labs_use_next_interface': True,
            'flutter.next_harness_path': str(harness),
        }))
        # The existing Lab source still starts without changing user config.
        (home / 'config.toml').write_text(
            f'model={json.dumps(model)}\nmodel_provider="cpa"\n'
            'cli_auth_credentials_store="ephemeral"\n'
            '[model_providers.cpa]\nname="cpa"\n'
            f'base_url={json.dumps(address)}\nwire_api="responses"\n'
            'env_key="NIPAPLAY_MODEL_API_KEY"\nrequires_openai_auth=false\n'
            '[features]\nshell_snapshot=false\n'
            '[shell_environment_policy]\nexclude=["NIPAPLAY_MODEL_API_KEY"]\n')
        shutil.copyfile('/etc/ssl/cert.pem', root / 'ca.pem')
        env = dict(os.environ, NIPAPLAY_PROFILE=profile,
                   NIPAPLAY_CODEX_EXECUTABLE=str(binary), NIPAPLAY_MODEL_API_KEY=key,
                   CODEX_CA_CERTIFICATE=str(root / 'ca.pem'), SSL_CERT_FILE=str(root / 'ca.pem'))
        env.pop('NIPAPLAY_LAB_QUIET', None)
        phase = 'startup'
        with (root / 'instance.log').open('wb') as output:
            process = subprocess.Popen([str(app)], env=env, stdout=output, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError('Lab exited before readiness')
            try:
                vm = VM(root / 'instance.log')
                state = vm.chat('status')
                if state['header']['mainThreadId'] is not None:
                    break
            except (RuntimeError, OSError, StopIteration):
                pass
            if vm:
                vm.socket.close()
                vm = None
            time.sleep(0.5)
        if vm is None:
            raise RuntimeError('Readiness timed out')
        record_pids()
        # Inspect process executable paths only; never argv or environment.
        executables = subprocess.check_output(['/bin/ps', '-axo', 'pid=,comm='], text=True)
        summary['downloadedExecutableObserved'] = any(
            line.split(maxsplit=1)[0].isdigit() and int(line.split(maxsplit=1)[0]) in owned
            and str(binary) in line for line in executables.splitlines())
        assert summary['downloadedExecutableObserved']
        phase = 'custom turn'
        vm.settings('setModel', choice=json.dumps({'source': 'nipaplay', 'provider': '自定义',
                    'baseUrl': address, 'model': model, 'apiKey': key}))
        started = time.monotonic()
        vm.chat('turn', text='只回复 X61_OK，不调用工具。')
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            state = vm.chat('status')
            if state['liveness']['status'] not in ('starting', 'inProgress', 'idle'):
                break
            time.sleep(0.25)
        record_pids()
        summary['turn'] = {'status': state['liveness']['status'],
                           'actualModel': state['header']['model'],
                           'actualProvider': state['header']['provider'],
                           'elapsedMs': int((time.monotonic() - started) * 1000)}
        if state['liveness']['status'] != 'completed':
            raise RuntimeError('Custom endpoint turn did not complete')
        phase = 'wrong key check'
        vm.settings('setModel', choice=json.dumps({'source': 'nipaplay', 'provider': '自定义',
                    'baseUrl': address, 'model': model, 'apiKey': wrong}))
        summary['wrongKey'] = vm.settings('checkModel')
        phase = 'chat-only check'
        vm.settings('setModel', choice=json.dumps({'source': 'nipaplay', 'provider': '自定义',
                    'baseUrl': f'http://127.0.0.1:{server.server_port}/v1',
                    'model': 'chat-only', 'apiKey': 'fixture-only'}))
        summary['chatOnly'] = vm.settings('checkModel')
        summary['userConfigUnchanged'] = hashlib.sha256(user_config.read_bytes()).hexdigest() == config_hash
        matches = []
        scanned = 0
        for path in root.rglob('*'):
            if path.is_file():
                scanned += 1
                data = path.read_bytes()
                if any(secret in data for secret in private):
                    matches.append(str(path.relative_to(root)))
        summary['secretScan'] = {'files': scanned, 'matches': matches}
        assert not matches
        assert summary['wrongKey']['ok'] is False
        assert '密钥' in summary['wrongKey']['message']
        assert summary['chatOnly']['message'] == '端点不支持 Responses 接口'
        vm.chat('close')
        summary['completed'] = True
    except Exception:
        summary['failedPhase'] = phase
        summary['completed'] = False
        raise RuntimeError('X61 experiment failed; sanitized phase recorded') from None
    finally:
        record_pids()
        if vm:
            vm.socket.close()
        for pid in sorted(owned, reverse=True):
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if process:
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        for pid in owned:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        server.shutdown()
        server.server_close()
        shutil.rmtree(root, ignore_errors=True)
        summary['profileRemoved'] = not root.exists()
        summary['ownedPids'] = sorted(owned)
        save()
        # Remove the runtime after the successful experiment; preserve a failed
        # download for a focused retry, without touching other profiles.
        if summary.get('completed'):
            shutil.rmtree(download)


if __name__ == '__main__':
    main()
