#!/usr/bin/env python3
"""Quiet worktree-only lab experiment. Credentials never enter argv or files."""
import argparse
import base64
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import socket
import struct
import subprocess
import time
import tomllib
import urllib.parse
import urllib.request


class VM:
    """Minimal stdlib WebSocket driver; secret parameters travel in RPC frames."""
    def __init__(self, log):
        match = re.search(r"Dart VM service is listening on (http://[^\s]+)",
                          log.read_text(errors="replace"))
        if not match:
            raise RuntimeError("VM service not ready")
        uri = urllib.parse.urlparse(match[1])
        self.socket = socket.create_connection((uri.hostname, uri.port), timeout=45)
        nonce = base64.b64encode(secrets.token_bytes(16)).decode()
        request = (f"GET {uri.path.rstrip('/')}/ws HTTP/1.1\r\n"
                   f"Host: {uri.hostname}:{uri.port}\r\nUpgrade: websocket\r\n"
                   f"Connection: Upgrade\r\nSec-WebSocket-Key: {nonce}\r\n"
                   "Sec-WebSocket-Version: 13\r\n\r\n")
        self.socket.sendall(request.encode())
        header = bytearray()
        while not header.endswith(b"\r\n\r\n"):
            header.extend(self.read(1))
        if not header.startswith(b"HTTP/1.1 101"):
            raise RuntimeError("VM WebSocket unavailable")
        self.sequence = 0
        info = self.rpc("getVM")
        self.isolate = next(i["id"] for i in info["isolates"] if i["name"] == "main")

    def read(self, size):
        data = bytearray()
        while len(data) < size:
            block = self.socket.recv(size - len(data))
            if not block:
                raise RuntimeError("VM connection ended")
            data.extend(block)
        return bytes(data)

    def send(self, body, opcode=1):
        mask = secrets.token_bytes(4)
        size = len(body)
        header = bytes([0x80 | opcode])
        if size < 126:
            header += bytes([0x80 | size])
        elif size < 65536:
            header += bytes([0x80 | 126]) + struct.pack("!H", size)
        else:
            header += bytes([0x80 | 127]) + struct.pack("!Q", size)
        self.socket.sendall(header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(body)))

    def receive(self):
        parts = bytearray()
        while True:
            first, second = self.read(2)
            length = second & 0x7f
            if length == 126:
                length = struct.unpack("!H", self.read(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self.read(8))[0]
            mask = self.read(4) if second & 0x80 else None
            body = self.read(length)
            if mask:
                body = bytes(b ^ mask[i % 4] for i, b in enumerate(body))
            opcode = first & 0x0f
            if opcode == 9:
                self.send(body, 10)
                continue
            if opcode == 8:
                raise RuntimeError("VM closed connection")
            parts.extend(body)
            if first & 0x80:
                return json.loads(parts)

    def rpc(self, method, **params):
        self.sequence += 1
        self.send(json.dumps({"jsonrpc": "2.0", "id": self.sequence,
                              "method": method, "params": params}).encode())
        while True:
            result = self.receive()
            if result.get("id") == self.sequence:
                if "error" in result:
                    raise RuntimeError("VM operation failed")
                return result["result"]

    def settings(self, op, **params):
        return self.rpc("ext.nipaplay.hostSettings", isolateId=self.isolate, op=op, **params)

    def chat(self, op, **params):
        return self.rpc("ext.nipaplay.chat", isolateId=self.isolate, op=op, **params)


def credentials():
    # Only this script reads the original provider. Never print config or errors.
    config = tomllib.loads((Path.home() / ".codex/config.toml").read_text())
    provider = config["model_providers"]["cpa"]
    key = provider.get("experimental_bearer_token")
    if not key and provider.get("env_key"):
        key = os.environ.get(provider["env_key"])
    if not key:
        raise RuntimeError("cpa credential unavailable")
    if provider.get("wire_api", "responses") != "responses":
        raise RuntimeError("cpa requires Responses API")
    return provider["base_url"].rstrip("/"), config["model"], key


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default="build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay")
    parser.add_argument("--reuse-correct-check", help="Evidence from an unchanged, already passed check")
    parser.add_argument("--reuse-wrong-check", help="Evidence from an unchanged, already passed wrong-key check")
    parser.add_argument("--state-only", action="store_true", help="Verify public state without repeating model requests")
    args = parser.parse_args()
    workspace = Path(__file__).resolve().parents[2]
    app = (workspace / args.app).resolve()
    if not app.is_relative_to(workspace / "build") or not app.is_file():
        raise RuntimeError("Use this worktree's executable")
    profile = "x52-host-" + secrets.token_hex(5)
    root = Path.home() / "Library/Application Support/NipaPlay/LabProfiles" / profile
    evidence = workspace / "docs/next/evidence/x52"
    evidence.mkdir(parents=True, exist_ok=True)
    address, model, key = credentials()
    wrong = "x52-invalid-" + secrets.token_hex(18)
    process = vm = None
    summary = {"profile": profile, "protocol": "Responses API", "configuredLabel": "DeepSeek"}
    try:
        root.mkdir(parents=True, mode=0o700)
        (root / "codex-home").mkdir()
        harness = root / "harness"
        (root / "preferences.json").write_text(json.dumps({
            "flutter.labs_enable_agent_endpoint": True,
            "flutter.labs_use_next_interface": True,
            "flutter.next_harness_path": str(harness),
        }))
        # Original LabProfile home still wins for source=codex. No credential file.
        original = (f"model={json.dumps(model)}\nmodel_provider=\"cpa\"\n"
                    "cli_auth_credentials_store=\"ephemeral\"\n"
                    "[model_providers.cpa]\nname=\"cpa\"\n"
                    f"base_url={json.dumps(address)}\nwire_api=\"responses\"\n"
                    "env_key=\"NIPAPLAY_MODEL_API_KEY\"\nrequires_openai_auth=false\n"
                    "[shell_environment_policy]\nexclude=[\"NIPAPLAY_MODEL_API_KEY\"]\n"
                    f"[projects.{json.dumps(str(harness))}]\ntrust_level=\"trusted\"\n")
        (root / "codex-home/config.toml").write_text(original)
        shutil.copyfile("/etc/ssl/cert.pem", root / "ca.pem")
        env = dict(os.environ, NIPAPLAY_PROFILE=profile, NIPAPLAY_MODEL_API_KEY=key,
                   CODEX_CA_CERTIFICATE=str(root / "ca.pem"), SSL_CERT_FILE=str(root / "ca.pem"))
        env.pop("NIPAPLAY_LAB_QUIET", None)
        log = root / "instance.log"
        with log.open("wb") as output:
            process = subprocess.Popen([str(app)], env=env, stdout=output, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError("Lab process exited before readiness")
            try:
                vm = VM(log)
                status = vm.chat("status")
                if status["header"]["mainThreadId"] is None:
                    vm.socket.close()
                    vm = None
                    time.sleep(0.5)
                    continue
                break
            except (RuntimeError, OSError, StopIteration):
                if vm:
                    vm.socket.close()
                    vm = None
                time.sleep(0.5)
        if vm is None:
            raise RuntimeError("Lab readiness timed out")
        initial = status["header"]["mainThreadId"]
        summary["initialModel"] = status["header"]["model"]

        def set_model(source, api_key=None):
            choice = {"source": source}
            if source == "nipaplay":
                choice.update(provider="DeepSeek", baseUrl=address, model=model)
                if api_key is not None:
                    choice["apiKey"] = api_key
            vm.settings("setModel", choice=json.dumps(choice))

        def turn(prompt):
            started = time.monotonic()
            result = vm.chat("turn", text=prompt)
            turn_id = result["turn"]["id"]
            deadline = started + 150
            while time.monotonic() < deadline:
                state = vm.chat("status")
                live = state["liveness"]
                if live.get("turnId") == turn_id and live.get("status") not in {"starting", "inProgress"}:
                    if live["status"] != "completed":
                        raise RuntimeError("Model turn failed")
                    if state["header"]["mainThreadId"] != initial or state["header"]["threadId"] != initial:
                        raise RuntimeError("Thread changed during switch")
                    return {"status": live["status"], "model": state["header"]["model"],
                            "provider": state["header"]["provider"], "threadUnchanged": True,
                            "elapsedMs": round((time.monotonic() - started) * 1000)}
                time.sleep(0.4)
            raise RuntimeError("Turn observation timed out")

        set_model("nipaplay", key)
        if args.state_only:
            set_model("codex")
            credential = json.loads((root / "endpoint.json").read_text())
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            request = urllib.request.Request(credential["url"],
                data=json.dumps({"operation": "call", "action": "state.query",
                    "input": {"view": "activity", "limit": 200}}).encode(),
                headers={"Authorization": "Bearer " + credential["token"],
                         "Content-Type": "application/json"})
            with opener.open(request, timeout=30) as response:
                public = json.load(response)
            if public.get("status") != "completed":
                raise RuntimeError("Public activity query failed")
            if any(s in json.dumps(public) for s in [key, wrong]):
                raise RuntimeError("Secret found in public state")
            changes = [row for row in public["result"]["rows"]
                       if row["type"] == "host_settings.changed"]
            if len(changes) != 2 or any(row["actor"] != "user" for row in changes):
                raise RuntimeError("Host actor attribution failed")
            summary["publicState"] = {"view": "activity", "hostChanges": len(changes),
                                      "allActorsUser": True, "secretAbsent": True}
            (evidence / "activity-state.json").write_text(json.dumps(public, ensure_ascii=False, indent=2) + "\n")
            vm.chat("close")
            vm.socket.close()
            vm = None
            process.terminate()
            process.wait(timeout=15)
            files = [p for p in root.rglob("*") if p.is_file() and not p.is_symlink()]
            leaks = sum(any(s.encode() in p.read_bytes() for s in [key, wrong]) for p in files)
            summary["secretScan"] = {"files": len(files), "leaks": leaks}
            if leaks:
                raise RuntimeError("Secret scan failed")
            summary["processExited"] = True
            summary["complete"] = True
            return 0
        if args.reuse_correct_check:
            prior = json.loads((evidence / args.reuse_correct_check).read_text())
            summary["correctCheck"] = prior["correctCheck"]
            summary["correctCheckReusedFrom"] = args.reuse_correct_check
        else:
            summary["correctCheck"] = vm.settings("checkModel")
        if not summary["correctCheck"]["ok"]:
            raise RuntimeError("Correct configuration check failed")
        summary["managedTurn"] = turn("只回复：X52 模型切换成功。不要调用工具。")
        set_model("nipaplay", wrong)
        if args.reuse_wrong_check:
            prior = json.loads((evidence / args.reuse_wrong_check).read_text())
            summary["wrongKeyCheck"] = prior["wrongKeyCheck"]
            summary["wrongKeyCheckReusedFrom"] = args.reuse_wrong_check
        else:
            summary["wrongKeyCheck"] = vm.settings("checkModel")
        if summary["wrongKeyCheck"]["ok"]:
            raise RuntimeError("Wrong key unexpectedly accepted")
        set_model("codex")
        summary["originalTurn"] = turn("只回复：X52 已切回原来的来源。不要调用工具。")
        history = vm.chat("read", threadId=initial)
        summary["historyTurns"] = len(history["turns"])
        summary["originalLabConfigUnchanged"] = (root / "codex-home/config.toml").read_text() == original
        vm.chat("close")
        vm.socket.close()
        vm = None
        process.terminate()
        process.wait(timeout=15)
        summary["processExited"] = True
        # Inspect activities and public state through the real endpoint.
        # A separate integration test invokes state.query and scans its envelope.
        import sqlite3
        database = root / "data/next/next.db"
        if database.exists():
            with sqlite3.connect(database) as connection:
                summary["userChanges"] = connection.execute(
                    "SELECT count(*) FROM body_changes WHERE type='host_settings.changed' AND actor='user' AND origin='gui'").fetchone()[0]
        files = [p for p in root.rglob("*") if p.is_file() and not p.is_symlink()]
        leak_paths = [str(p.relative_to(root)) for p in files
                      if any(s.encode() in p.read_bytes() for s in [key, wrong])]
        leaked = len(leak_paths)
        summary["secretScan"] = {"files": len(files), "leaks": leaked,
                                  "vaultFileExists": (root / "credential-vault.json").exists(),
                                  "paths": leak_paths}
        if leaked:
            raise RuntimeError("Secret scan failed")
        safe_log = log.read_text(errors="replace")
        safe_log = re.sub(r"http://127\.0\.0\.1:\d+/[^\s]+", "[VM URI omitted]", safe_log)
        (evidence / "lab.log").write_text(safe_log)
        summary["complete"] = True
    except Exception as error:
        summary["complete"] = False
        summary["failure"] = type(error).__name__
        # Fixed messages only; no upstream response, secret value or URL.
        summary["reason"] = str(error) if isinstance(error, RuntimeError) else "Experiment operation failed"
    finally:
        if vm:
            try:
                vm.chat("close")
            except Exception:
                pass
            vm.socket.close()
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        shutil.rmtree(root)
        summary["profileRemoved"] = not root.exists()
        destination = "state-experiment.json" if args.state_only else "experiment.json"
        (evidence / destination).write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
        print(json.dumps(summary, ensure_ascii=False))
    return 0 if summary.get("complete") else 1


if __name__ == "__main__":
    raise SystemExit(main())
