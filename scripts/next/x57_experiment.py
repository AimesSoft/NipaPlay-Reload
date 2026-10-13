#!/usr/bin/env python3
"""X57 real integration, owned quiet worktree process, memory-only model keys."""
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import secrets
import shutil
import subprocess
import time
import urllib.request

from x52_experiment import VM, credentials

WORKSPACE = Path(__file__).resolve().parents[2]
EVIDENCE = WORKSPACE / "docs/next/evidence/x57"


def main():
    app = WORKSPACE / "build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay"
    if not app.is_file() or not app.resolve().is_relative_to(WORKSPACE / "build"):
        raise RuntimeError("Use this worktree's build")
    label = os.environ.get("X57_EVIDENCE_LABEL", "integration")
    out = EVIDENCE / label
    out.mkdir(parents=True, exist_ok=False)
    profile = "x57-verify-" + secrets.token_hex(5)
    root = Path.home() / "Library/Application Support/NipaPlay/LabProfiles" / profile
    address, model, key = credentials()
    wrong = "x57-invalid-" + secrets.token_hex(18)
    private = [key, wrong]
    process = vm = None
    owned_pids = set()
    summary = {"profile": profile, "baseline": "3dcac152", "codexVersion": "0.144.1"}
    summary["sourceHashes"] = {name: hashlib.sha256((WORKSPACE / name).read_bytes()).hexdigest()
        for name in ["lib/next/chat/chat_host.dart", "lib/next/memory/recent.dart",
                     "lib/next/ui/settings/section_host.dart", "assets/next/harness/AGENTS.md"]}

    def record_processes():
        if process is None or process.poll() is not None:
            return
        pairs = [tuple(map(int, line.split())) for line in
                 subprocess.check_output(["/bin/ps", "-axo", "pid=,ppid="], text=True).splitlines()]
        descendants = {process.pid}
        while True:
            extra = {pid for pid, parent in pairs if parent in descendants} - descendants
            if not extra:
                break
            descendants.update(extra)
        owned_pids.update(descendants)

    def alive(pid):
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False

    def safe(value):
        text = json.dumps(value, ensure_ascii=False)
        for secret in private:
            text = text.replace(secret, "[redacted]")
        text = text.replace(address, "[provider address omitted]")
        text = re.sub(r"http://127\.0\.0\.1:\d+/[^\s\"\\]+", "[VM URI omitted]", text)
        return json.loads(text)

    def save(name, value):
        (out / name).write_text(json.dumps(safe(value), ensure_ascii=False, indent=2) + "\n")

    def events():
        file = root / "chat-events.jsonl"
        return [json.loads(line) for line in file.read_text().splitlines()] if file.exists() else []

    def snapshot(name):
        window_id = subprocess.check_output(["/tmp/nipa-next/x57-window", str(process.pid)], text=True).strip()
        subprocess.run(["/usr/sbin/screencapture", "-x", "-o", "-t", "jpg", "-l" + window_id,
                        str(out / (name + ".jpg"))], check=True, capture_output=True)
        summary.setdefault("screenshots", []).append({"file": name + ".jpg", "pid": process.pid,
                                                      "windowId": int(window_id)})

    try:
        root.mkdir(parents=True, mode=0o700)
        home = root / "codex-home"
        home.mkdir(mode=0o700)
        # No project or hook trust in this fresh default home; host must supply it.
        original = (f"model={json.dumps(model)}\nmodel_provider=\"cpa\"\n"
                    "cli_auth_credentials_store=\"ephemeral\"\n"
                    "[model_providers.cpa]\nname=\"cpa\"\n"
                    f"base_url={json.dumps(address)}\nwire_api=\"responses\"\n"
                    "env_key=\"NIPAPLAY_MODEL_API_KEY\"\nrequires_openai_auth=false\n"
                    "[shell_environment_policy]\nexclude=[\"NIPAPLAY_MODEL_API_KEY\"]\n")
        (home / "config.toml").write_text(original)
        (home / "config.toml").chmod(0o600)
        harness = root / "harness"
        shutil.copytree(WORKSPACE / "assets/next/harness", harness)
        subprocess.run(["git", "init", "--quiet", "--template=", "--initial-branch=main"],
                       cwd=harness, check=True, capture_output=True)
        seed_marker = "X57_SEED_" + secrets.token_hex(5)
        recent_marker = "X57_RECENT_" + secrets.token_hex(5)
        (harness / "AGENTS.md").write_text((harness / "AGENTS.md").read_text() +
            "\n本隔离实验只操作当前 harness 和连接实例；不读用户文件、不读钥匙串、不启动其他程序。"
            "回合不要调用工具，不写记忆。实验种子代号：" + seed_marker + "。\n")

        def memory_marker():
            marker = "X57_PREF_" + secrets.token_hex(5)
            (harness / "memory/preferences.md").write_text(
                "2026-10-13：推荐一次给 2 部；当前偏好验证代号 " + marker + "。（出处：隔离实验用户）\n")
            return marker

        pref = memory_marker()
        (root / "preferences.json").write_text(json.dumps({
            "flutter.labs_enable_agent_endpoint": True, "flutter.labs_use_next_interface": True,
            "flutter.next_harness_path": str(harness), "flutter.auto_sync_enabled": False,
            "flutter.downloader_enabled": False, "flutter.player_volume": 0.0,
        }))
        if os.environ.get("X57_UI_ONLY") == "1":
            settings_root = root / "data/next"
            settings_root.mkdir(parents=True)
            (settings_root / "program.json").write_text('{"enabled":true}')
        shutil.copyfile("/etc/ssl/cert.pem", root / "ca.pem")
        env = dict(os.environ, NIPAPLAY_PROFILE=profile, NIPAPLAY_MODEL_API_KEY=key,
                   CODEX_CA_CERTIFICATE=str(root / "ca.pem"), SSL_CERT_FILE=str(root / "ca.pem"))
        for name in list(env):
            if name == "NIPAPLAY_LAB_QUIET" or name.startswith("NIPAPLAY_NEXT_UI_FAKE"):
                env.pop(name)
        log = root / "instance.log"
        with log.open("wb") as output:
            process = subprocess.Popen([str(app)], cwd=WORKSPACE, env=env,
                                       stdout=output, stderr=subprocess.STDOUT)
        summary["appPid"] = process.pid
        deadline = time.monotonic() + 150
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError("Owned app exited before readiness")
            try:
                vm = VM(log)
                state = vm.chat("status")
                if state["header"]["mainThreadId"] and state["header"]["model"]:
                    break
            except (RuntimeError, OSError, StopIteration):
                pass
            if vm:
                vm.socket.close()
                vm = None
            time.sleep(0.5)
        if vm is None:
            raise RuntimeError("Readiness timeout")
        if vm.rpc("getVM")["pid"] != process.pid:
            raise RuntimeError("VM is not the owned process")
        initial = state["header"]["mainThreadId"]
        summary["mainThreadId"] = initial
        connection = json.loads((root / "endpoint.json").read_text())
        private.append(connection["token"])
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))

        def call(action, inputs):
            request = urllib.request.Request(connection["url"], data=json.dumps({
                "operation": "call", "action": action, "input": inputs}).encode(),
                headers={"Content-Type": "application/json", "Authorization": "Bearer " + connection["token"]})
            with opener.open(request, timeout=45) as response:
                result = json.load(response)
            if result["status"] != "completed":
                raise RuntimeError("Fixture action failed")
            return result["result"]

        def ui(section):
            result = vm.rpc("ext.nipaplay.nextui", isolateId=vm.isolate,
                            op="settings", section=section, reload="true")
            save("ui-" + section + ".json", result)
            return result

        def turn(label, prompt, expected=()):
            offset = len(events())
            started = time.monotonic()
            response = vm.chat("turn", text=prompt)
            turn_id = response["turn"]["id"]
            deadline = started + 180
            while time.monotonic() < deadline:
                record_processes()
                status = vm.chat("status")
                live = status["liveness"]
                if live.get("turnId") == turn_id and live["status"] not in {"starting", "inProgress"}:
                    break
                time.sleep(0.4)
            if live.get("status") != "completed":
                raise RuntimeError("Model turn did not complete")
            messages = [entry["m"] for entry in events()[offset:]]
            hooks = [message["params"] for message in messages if message.get("method") == "hook/completed"]
            replies = [message["params"]["item"]["text"] for message in messages
                       if message.get("method") == "item/completed" and
                       message["params"]["item"]["type"] == "agentMessage"]
            result = {"header": status["header"], "turnId": turn_id, "status": live["status"],
                      "elapsedMs": round((time.monotonic() - started) * 1000), "replies": replies,
                      "hookCompletions": hooks,
                      "commands": sum(message.get("method") == "item/started" and
                                      message["params"]["item"]["type"] == "commandExecution" for message in messages),
                      "expectedMarkers": list(expected)}
            text = "\n".join(replies)
            result["markersReadWithoutTools"] = all(marker in text for marker in expected) and result["commands"] == 0
            result["hookRan"] = any(hook["run"]["status"] == "completed" for hook in hooks)
            save(label + ".json", result)
            if not result["markersReadWithoutTools"] or not result["hookRan"]:
                raise RuntimeError("Context markers were not read")
            return result

        if os.environ.get("X57_UI_ONLY") == "1":
            summary["model"] = vm.settings("model")
            summary["mesh"] = call("mesh.devices", {})
            summary["remotePrograms"] = vm.settings("remotePrograms")
            ui("nipa")
            snapshot("nipa-default")
            ui("devices")
            snapshot("devices")
            summary["modelRequests"] = 0
            summary["complete"] = True
            return 0

        # Establish real prior user/assistant words without synthetic history files.
        vm.chat("start")
        turn("recent-fixture", "只回复这个代号：" + recent_marker + "。不要调用工具。")
        vm.chat("main")
        prompt = "不要调用工具。只列出实验种子代号、当前偏好验证代号、刚才对话里以 X57_RECENT_ 开头的代号和推荐数量。"
        summary["defaultTurn"] = turn("default-turn", prompt, (seed_marker, pref, recent_marker))
        ui("nipa")
        snapshot("nipa-default")

        def set_model(source, api_key=None):
            choice = {"source": source}
            if source == "nipaplay":
                choice.update(provider="DeepSeek", baseUrl=address, model=model)
                if api_key is not None:
                    choice["apiKey"] = api_key
            vm.settings("setModel", choice=json.dumps(choice))

        pref = memory_marker()
        set_model("nipaplay", key)
        if os.environ.get("X57_REUSE_CORRECT_CHECK"):
            summary["correctCheck"] = json.loads(Path(os.environ["X57_REUSE_CORRECT_CHECK"]).read_text())["correctCheck"]
            summary["correctCheckReusedFrom"] = os.environ["X57_REUSE_CORRECT_CHECK"]
        else:
            summary["correctCheck"] = vm.settings("checkModel")
        if not summary["correctCheck"]["ok"]:
            raise RuntimeError("Correct-key check failed")
        summary["managedTurn"] = turn("managed-turn", prompt, (seed_marker, pref))
        summary["managedModel"] = vm.settings("model")
        ui("nipa")
        snapshot("nipa-managed")
        ui("devices")
        snapshot("devices")
        summary["mesh"] = call("mesh.devices", {})
        summary["remotePrograms"] = vm.settings("remotePrograms")
        set_model("nipaplay", wrong)
        summary["wrongKeyCheck"] = vm.settings("checkModel")
        if summary["wrongKeyCheck"]["ok"]:
            raise RuntimeError("Wrong-key check unexpectedly passed")
        pref = memory_marker()
        set_model("codex")
        summary["returnedTurn"] = turn("returned-turn", prompt, (seed_marker, pref))
        summary["returnedModel"] = vm.settings("model")
        ui("nipa")
        snapshot("nipa-returned")
        history = vm.chat("read", threadId=initial)
        save("main-history.json", history)
        summary["mainHistoryTurns"] = len(history["turns"])
        summary["mainThreadUnchanged"] = all(summary[name]["header"]["threadId"] == initial and
            summary[name]["header"]["mainThreadId"] == initial for name in ["defaultTurn", "managedTurn", "returnedTurn"])
        summary["defaultConfigUnchanged"] = (home / "config.toml").read_text() == original
        summary["originalHookUnchanged"] = all((harness / name).read_bytes() == (WORKSPACE / "assets/next/harness" / name).read_bytes()
            for name in [".codex/hooks.json", "hooks/session_start.py"])
        summary["hookTrust"] = vm.chat("hooks")
        save("activity.json", call("state.query", {"view": "activity", "limit": 100}))
        save("events.json", events())
        summary["complete"] = summary["mainThreadUnchanged"] and summary["mainHistoryTurns"] == 3
    except Exception as error:
        summary["complete"] = False
        summary["failureType"] = type(error).__name__
        # No exception text: upstream responses or paths may contain credentials.
        if vm:
            try:
                save("failure-events.json", events())
                save("failure-status.json", vm.chat("status"))
            except Exception:
                pass
    finally:
        record_processes()
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
        # Terminate only descendants actually observed under this Popen PID.
        remaining = [pid for pid in owned_pids if alive(pid)]
        for pid in remaining:
            os.kill(pid, signal.SIGTERM)
        deadline = time.monotonic() + 3
        while any(alive(pid) for pid in remaining) and time.monotonic() < deadline:
            time.sleep(0.1)
        for pid in remaining:
            if alive(pid):
                os.kill(pid, signal.SIGKILL)
        summary["ownedPids"] = sorted(owned_pids)
        summary["remainingOwnedPids"] = [pid for pid in owned_pids if alive(pid)]
        summary["appExited"] = process is None or process.poll() is not None
        if root.exists():
            # Endpoint/VM tokens are intentional live connection files. Model keys
            # must not appear anywhere, including config, logs, rollout or journal.
            files = [p for p in root.rglob("*") if p.is_file() and not p.is_symlink()]
            leaks = [str(p.relative_to(root)) for p in files if any(secret.encode() in p.read_bytes() for secret in [key, wrong])]
            summary["modelSecretScan"] = {"files": len(files), "leaks": len(leaks), "paths": leaks,
                                          "snapshots": sum("shell_snapshots" in p.parts for p in files)}
            summary["journalScanned"] = [str(p.relative_to(root)) for p in files if "journal" in p.name]
            summary["rolloutScanned"] = sum(p.name.startswith("rollout-") for p in files)
            if leaks:
                summary["complete"] = False
            if (root / "instance.log").exists():
                save("lab-log.json", {"text": (root / "instance.log").read_text(errors="replace")})
            shutil.rmtree(root)
        summary["profileRemoved"] = not root.exists()
        # Only already-sanitized evidence is retained.
        save("summary.json", summary)
        evidence_files = [p for p in out.rglob("*") if p.is_file()]
        evidence_leaks = sum(any(secret.encode() in p.read_bytes() for secret in private) for p in evidence_files)
        save("cleanup.json", {"pid": summary.get("appPid"), "appExited": summary["appExited"],
             "ownedPids": summary["ownedPids"], "remainingOwnedPids": summary["remainingOwnedPids"],
             "profileRemoved": summary["profileRemoved"], "modelSecretScan": summary.get("modelSecretScan"),
             "evidenceFiles": len(evidence_files), "evidenceSecretMatches": evidence_leaks})
        print(json.dumps({"complete": summary.get("complete"), "failureType": summary.get("failureType"),
                          "appExited": summary["appExited"], "profileRemoved": summary["profileRemoved"],
                          "secretMatches": evidence_leaks}))
    return 0 if summary.get("complete") and evidence_leaks == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
