"""Offline probe of the generated workspace with the installed Codex CLI."""

import http.server
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import threading


def main():
    repo = Path(__file__).resolve().parents[2]
    print(subprocess.check_output(["codex", "--version"], text=True).strip())
    with tempfile.TemporaryDirectory(prefix="nipaplay-codex-x1-") as temporary:
        root = Path(temporary)
        workspace = root / "workspace"
        generator = root / "generate.dart"
        generator.write_text("""import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'WORKSPACE_SOURCE';
Future<void> main(List<String> args) => writeAgentWorkspace(
  directory: Directory(args.single), url: Uri.parse('http://127.0.0.1:9/mcp'),
  token: 'synthetic-probe-token', agentsMd: '# Offline configuration probe\\n',
  catalog: [for (final id in ['download.delete', 'danmaku.cache_delete', 'mesh.invoke_destructive'])
    ActionSpec(id: id, title: id, description: id, effect: Effect.destructive,
      input: const ObjectSchema({}), output: const ObjectSchema({}))]);
""".replace("WORKSPACE_SOURCE", (repo / "lib/next/agent_workspace.dart").as_uri()))
        subprocess.run([
            str(Path("~/development/flutter-3.44.6/bin/dart").expanduser()),
            "--packages=" + str(repo / ".dart_tool/package_config.json"),
            str(generator), str(workspace),
        ], cwd=repo, check=True)
        assert (workspace / ".codex/config.toml").stat().st_mode & 0o777 == 0o600
        print("config file mode: 600")
        home = root / "codex-home"
        home.mkdir()
        requests = []
        command = "python3 -c " + shlex.quote(
            "import pathlib,urllib.request; p=pathlib.Path(" + repr(str(root / "outside.txt"))
            + '); p.write_text("outside workspace"); print(p.read_text()); p.unlink(); '
            + 'print(urllib.request.urlopen("http://127.0.0.1:PORT/probe").read().decode())'
        )

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"network available")

            def do_POST(self):
                request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                requests.append(request)
                if len(requests) == 1:
                    names = [tool.get("name", tool.get("type")) for tool in request["tools"]]
                    assert "web_search" in names
                    print("live web_search tool: present")
                    item = {"type": "function_call", "id": "fc_probe", "call_id": "probe",
                            "name": "exec_command", "arguments": json.dumps({
                                "cmd": command, "yield_time_ms": 1000, "max_output_tokens": 1000})}
                else:
                    item = {"type": "message", "id": "msg_probe", "role": "assistant",
                            "status": "completed", "content": [{"type": "output_text",
                                "text": "Probe complete.", "annotations": []}]}
                response = {"id": "resp_" + str(len(requests)), "object": "response",
                            "status": "completed", "output": [item],
                            "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2}}
                events = [
                    {"type": "response.created", "response": dict(response, status="in_progress", output=[])},
                    {"type": "response.output_item.added", "output_index": 0, "item": item},
                    {"type": "response.output_item.done", "output_index": 0, "item": item},
                    {"type": "response.completed", "response": response},
                ]
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                for event in events:
                    self.wfile.write(("event: " + event["type"] + "\ndata: "
                                      + json.dumps(event) + "\n\n").encode())

        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        command = command.replace("PORT", str(server.server_port))
        (home / "config.toml").write_text('''model = "offline-probe"
model_provider = "offline"
[model_providers.offline]
name = "Offline probe"
base_url = "http://127.0.0.1:PORT/v1"
wire_api = "responses"
requires_openai_auth = false
'''.replace("PORT", str(server.server_port)) + "[projects."
            + json.dumps(str(workspace)) + ']\ntrust_level = "trusted"\n')
        with (root / "stderr.log").open("w") as stderr:
            process = subprocess.Popen(["codex", "app-server", "--strict-config"],
                cwd=workspace, env=dict(os.environ, CODEX_HOME=str(home)),
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=stderr,
                text=True, bufsize=1)
            sequence = 0

            def receive():
                line = process.stdout.readline()
                if not line:
                    raise RuntimeError("Codex closed before verification completed")
                message = json.loads(line)
                assert not message.get("method", "").endswith("requestApproval"), message
                return message

            def rpc(method, params):
                nonlocal sequence
                sequence += 1
                process.stdin.write(json.dumps(dict(id=sequence, method=method, params=params)) + "\n")
                process.stdin.flush()
                while True:
                    message = receive()
                    if message.get("id") == sequence:
                        if "error" in message:
                            raise RuntimeError(message["error"])
                        return message["result"]

            try:
                rpc("initialize", {"clientInfo": {"name": "nipaplay-x1-probe", "version": "1"},
                                   "capabilities": {"experimentalApi": True}})
                process.stdin.write('{"method":"initialized"}\n')
                process.stdin.flush()
                config = rpc("config/read", {"cwd": str(workspace), "includeLayers": True})
                for key, expected in {"sandbox_mode": "danger-full-access",
                                      "approval_policy": "never", "web_search": "live"}.items():
                    assert config["config"][key] == expected
                    assert config["origins"][key]["name"]["type"] == "project"
                    print(key + ": " + json.dumps(expected) + " (origin: project)")
                tools = config["config"]["mcp_servers"]["nipaplay"]["tools"]
                assert tools == {name: {"approval_mode": "prompt"} for name in [
                    "download_delete", "danmaku_cache_delete", "mesh_invoke_destructive"]}
                print("destructive tools: " + json.dumps(tools, sort_keys=True))
                thread = rpc("thread/start", {"cwd": str(workspace), "ephemeral": True})
                assert thread["approvalPolicy"] == "never"
                assert thread["sandbox"] == {"type": "dangerFullAccess"}
                print("thread: " + json.dumps({key: thread[key] for key in ["approvalPolicy", "sandbox"]}))
                rpc("turn/start", {"threadId": thread["thread"]["id"], "input": [{
                    "type": "text", "text": "Run the local configuration probe command supplied by the local fixture."}]})
                executed = False
                while True:
                    event = receive()
                    if event.get("method") == "item/completed" and event["params"]["item"].get("type") == "commandExecution":
                        item = event["params"]["item"]
                        assert item["exitCode"] == 0
                        assert item["aggregatedOutput"] == "outside workspace\nnetwork available\n"
                        executed = True
                        print("command execution: " + json.dumps({key: item[key] for key in ["exitCode", "aggregatedOutput", "status"]}))
                    if event.get("method") == "turn/completed":
                        assert executed and event["params"]["turn"]["status"] == "completed"
                        print("turn status: completed; approval requests: 0")
                        break
            finally:
                process.terminate()
                process.wait(timeout=10)
                server.shutdown()


if __name__ == "__main__":
    main()
