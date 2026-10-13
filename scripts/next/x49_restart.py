#!/usr/bin/env python3
"""Three real app-server restarts, preserving the same main conversation."""
from pathlib import Path

source = Path(__file__).with_name('x49_experiment.py').read_text()
exec(compile(source.split('\ntry:\n    for run in range', 1)[0],
             str(Path(__file__).with_name('x49_experiment.py')), 'exec'))
primary_evidence = evidence
evidence = evidence / 'restart'
evidence.mkdir(exist_ok=True)
shutil.copy2(primary_evidence / 'hook-trust-probe.json', evidence / 'hook-trust-probe.json')

try:
    launch(5)
    main = vm.chat('status')['header']['threadId']
    turn('initial', '我在挑周日电影夜片单。只回复收到，不用工具。')
    for repetition in range(1, 4):
        vm.chat('close')
        app.terminate()
        app.wait(timeout=20)
        record('stopped-%d' % repetition, {'pid': app.pid, 'returncode': app.returncode})
        (evidence / ('app-before-%d.log' % repetition)).write_text(safe((root / 'app.log').read_text(errors='replace')))
        (root / 'harness/memory/preferences.md').write_text(
            '# 偏好\n- 2026-10-13，实验用户：推荐时每次先给%d部。\n' % repetition)
        env = dict(os.environ, NIPAPLAY_PROFILE=root.name, CODEX_HOME=str(root / 'codex-home'),
            CODEX_CA_CERTIFICATE=str(root / 'system-ca.pem'), SSL_CERT_FILE=str(root / 'system-ca.pem'),
            NO_PROXY='127.0.0.1,localhost', no_proxy='127.0.0.1,localhost')
        env.pop('NIPAPLAY_LAB_QUIET', None)
        with (root / 'app.log').open('w') as output:
            app = subprocess.Popen([str(workspace / 'build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay')],
                env=env, stdout=output, stderr=subprocess.STDOUT)
        until(ready)
        assert vm.rpc('getVM')['pid'] == app.pid
        assert vm.chat('status')['header']['threadId'] == main
        record('same-main-%d' % repetition, {'threadId': main, 'pid': app.pid})
        turn('resume-after-restart-%d' % repetition,
             '我有什么推荐数量偏好？只回答现在的偏好，不用工具。')
    stop(5)
finally:
    if app is not None:
        stop(5)
    server.shutdown()
    server.server_close()
    with gzip.open(evidence / 'provider-inputs.json.gz', 'wt') as stream:
        json.dump(captures, stream, ensure_ascii=False)
