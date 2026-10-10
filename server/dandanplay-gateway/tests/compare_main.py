"""Compare main and the working gateway against a loopback-only mock upstream.

Run from any directory: python3 server/dandanplay-gateway/tests/compare_main.py
No external Python packages, real credentials, commits or remote API calls.
"""

import base64
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request


ROOT = Path(__file__).resolve().parents[3]
CRATE = ROOT / "server/dandanplay-gateway"
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
CAPTURED = []
LOCK = threading.Lock()


class Mock(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def handle_request(self):
        body = self.rfile.read(int(self.headers.get("content-length", "0")))
        token = self.headers.get("authorization", "").removeprefix("Bearer ")
        with LOCK:
            CAPTURED.append((self.command, self.path, dict(self.headers), body))
        status, payload = 201, b'{"success":true,"mock":"loopback"}'
        if self.path.startswith("/api/v2/playhistory?"):
            status, payload = 200, b'{"success":true}'
            if token in ("test-401", "test-403"):
                status = int(token.removeprefix("test-"))
            elif token == "test-false":
                payload = b'{"success":false}'
            elif token == "test-500":
                status = 500
            elif token == "test-json-error":
                payload = b"not json"
        self.send_response(status)
        for name, value in {
            "content-type": "application/json", "etag": "test-etag",
            "last-modified": "Wed, 01 Jan 2025 00:00:00 GMT", "location": "/next",
            "allow": "GET, POST", "www-authenticate": "Bearer",
            "x-error-message": "test-error", "set-cookie": "must-not-pass",
            "x-upstream-private": "must-not-pass", "content-length": str(len(payload)),
        }.items():
            self.send_header(name, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(payload)

    do_GET = do_POST = do_DELETE = do_HEAD = do_OPTIONS = handle_request


def request(port, method, path, token=None, body=None, headers=None):
    headers = dict(headers or {})
    if token is not None:
        headers["authorization"] = f"Bearer {token}"
    if isinstance(body, dict):
        body = json.dumps(body).encode()
        headers["content-type"] = "application/json"
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=body, headers=headers, method=method)
    try:
        response = OPENER.open(req, timeout=5)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        return response.status, {k.lower(): v for k, v in response.headers.items()
                                 if k.lower() not in ("date", "connection", "transfer-encoding")}, response.read()


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def normalize_call(call):
    method, path, headers, body = call
    headers = {key.lower(): value for key, value in headers.items()}
    timestamp = headers["x-timestamp"]
    source = f'nipaplayv1{timestamp}{path.split("?")[0]}test-app-secret'.encode()
    assert headers["x-signature"] == base64.b64encode(hashlib.sha256(source).digest()).decode(), path
    # Timestamps and account hashes can differ across processes by one second.
    if path.split("?")[0] in ("/api/v2/login", "/api/v2/register"):
        account = json.loads(body)
        if path == "/api/v2/login":
            hash_source = f'nipaplayv1{account["password"]}{timestamp}{account["userName"]}test-app-secret'
        else:
            hash_source = f'nipaplayv1{account["email"]}{account["password"]}{account["screenName"]}{timestamp}{account["userName"]}test-app-secret'
        assert account["hash"] == hashlib.md5(hash_source.encode()).hexdigest()
        assert account["unixTimestamp"] == int(timestamp)
        del account["hash"], account["unixTimestamp"]
        body = json.dumps(account, sort_keys=True).encode()
    for key in ("host", "x-timestamp", "x-signature", "content-length"):
        headers.pop(key, None)
    return method, path, headers, body


def run_gateway(binary, upstream_port, scenarios, settings, log_path):
    port = free_port()
    env = dict(os.environ)
    for name in tuple(env):
        if name.lower().endswith("proxy"):
            del env[name]
    env.update(LISTEN_ADDR=f"127.0.0.1:{port}", DANDANPLAY_UPSTREAM_BASE=f"http://127.0.0.1:{upstream_port}",
               DANDANPLAY_APP_ID="nipaplayv1", DANDANPLAY_APP_SECRET="test-app-secret",
               DANDANPLAY_USER_AGENT="NipaPlay/1.0", ALLOW_UNKNOWN_API_V2="true",
               MAX_REQUEST_BYTES="1024", ACCOUNT_REQUESTS_PER_MINUTE="120",
               IP_REQUESTS_PER_MINUTE="300", GLOBAL_REQUESTS_PER_MINUTE="3000", RUST_LOG="debug")
    env.update(settings)
    with open(log_path, "wb") as log:
        process = subprocess.Popen([str(binary)], env=env, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 10
            while True:
                try:
                    request(port, "GET", "/healthz")
                    break
                except (urllib.error.URLError, OSError):
                    if process.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError("gateway did not start")
                    time.sleep(0.02)
            with LOCK:
                CAPTURED.clear()
            responses = [request(port, *scenario) for scenario in scenarios]
            with LOCK:
                calls = [normalize_call(call) for call in CAPTURED]
            return responses, calls
        finally:
            process.terminate()
            process.wait(timeout=10)


def main():
    with tempfile.TemporaryDirectory(prefix="nipaplay-gateway-review-") as temp:
        temp = Path(temp)
        baseline = temp / "baseline"
        (baseline / "src").mkdir(parents=True)
        for name in ("Cargo.toml", "Cargo.lock", "src/main.rs"):
            content = subprocess.check_output(["git", "show", f"main:server/dandanplay-gateway/{name}"], cwd=ROOT)
            (baseline / name).write_bytes(content)
        target = CRATE / "target"
        subprocess.run(["cargo", "build", "--offline", "--locked", "--manifest-path", str(baseline / "Cargo.toml"), "--target-dir", str(target)], check=True)
        old_binary = temp / "gateway-main"
        shutil.copy2(target / "debug/nipaplay-dandanplay-gateway", old_binary)
        subprocess.run(["cargo", "build", "--offline", "--locked", "--manifest-path", str(CRATE / "Cargo.toml")], check=True)
        new_binary = target / "debug/nipaplay-dandanplay-gateway"
        account = {"userName": "test-user", "password": "test-password", "email": "test@example.test", "screenName": "Test", "hash": "forged"}
        scenarios = [("GET", "/healthz"), ("GET", "/outside"), ("POST", "/api/v2/login", None, account),
                     ("POST", "/api/v2/register", None, account), ("POST", "/api/v2/login", None, b"bad-json"),
                     ("POST", "/api/v2/login", None, b"x" * 1025)]
        for path in ("/api/v2/match", "/api/v2/comment/42", "/api/v2/bangumi/42", "/api/v2/search/anime", "/api/v2/future", "/api/v2/login/renew"):
            for method in ("GET", "POST", "HEAD", "DELETE"):
                scenarios.extend([(method, path), (method, path, "test-valid")])
        for token in ("test-401", "test-403", "test-false", "test-500", "test-json-error"):
            scenarios.extend([("GET", "/api/v2/bangumi/42", token)] * 2)
        for path in ("/api/v2/oauth/deleteAccount", "/api/v2/oauthprovider/bangumi/manage", "/api/v2/bangumi/42"):
            scenarios.append(("GET", f"{path}?webToken=test-web-secret"))
        scenarios.append(("OPTIONS", "/api/v2/match", None, None, {"origin": "https://example.test", "access-control-request-method": "POST"}))
        matrix = [({}, scenarios), ({"ALLOW_UNKNOWN_API_V2": "false"}, scenarios)]
        for kind in ("ACCOUNT", "IP", "GLOBAL"):
            matrix.append(({f"{kind}_REQUESTS_PER_MINUTE": "1"}, [
                ("GET", "/api/v2/bangumi/42", "test-a", None, {"x-real-ip": "203.0.113.1"}),
                ("GET", "/api/v2/bangumi/43", "test-a" if kind == "ACCOUNT" else "test-b", None,
                 {"x-real-ip": "203.0.113.2" if kind == "GLOBAL" else "203.0.113.1"})]))
        upstream = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Mock)
        thread = threading.Thread(target=upstream.serve_forever, daemon=True)
        thread.start()
        try:
            count = 0
            for i, (settings, cases) in enumerate(matrix):
                before = run_gateway(old_binary, upstream.server_port, cases, settings, temp / f"main-{i}.log")
                after = run_gateway(new_binary, upstream.server_port, cases, settings, temp / f"working-{i}.log")
                assert before == after, f"behavior differs for settings {settings}"
                count += len(cases)
                assert "test-web-secret" not in (temp / f"working-{i}.log").read_text()
            assert "test-web-secret" in (temp / "main-0.log").read_text(), "baseline should demonstrate the logging defect"
            print(f"PASS: {count} requests per gateway; responses, upstream requests, signatures, account hashes, caches and rate limits match main.")
            print("PASS: debug logs no longer contain the synthetic webToken (baseline reproduced the leak).")
        finally:
            upstream.shutdown()
            upstream.server_close()


if __name__ == "__main__":
    main()
