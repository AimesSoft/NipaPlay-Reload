"""Check documented Action IDs against known source registration forms.

This is a deliberately bounded check, not a Dart analyzer or live catalog.
See docs/next/development/ACTION_COVERAGE.md before interpreting its result.
"""
import re
import pathlib
import json
root = pathlib.Path(__file__).resolve().parents[2]
paths = list((root / 'lib/next').rglob('*.dart')) + list((root / 'lib/security').glob('*capability.dart')) + list((root / 'packages/nipa_harness/lib/src').rglob('*.dart'))
rows = {}

def add(i, p, desc='', eff='待自省'):
    if '$' in i or '.' not in i:
        return
    rows.setdefault(i, []).append([str(p.relative_to(root)), desc, eff])
for p in paths:
    if '/ui/dev/' in str(p):
        continue
    s = p.read_text()
    for m in re.finditer('\\bid:\\s*[\\\'"]([a-z][a-z0-9_]*(?:\\.[a-z0-9_]+)+)[\\\'"]', s):
        near = s[max(0, m.start() - 110):m.start()]
        if not re.search('ActionSpec\\s*\\([^()]*$', near, re.S):
            continue
        chunk = s[m.end():m.end() + 900]
        title = re.search('title:\\s*[\\\'"]([^\\\'"\\n]+)', chunk)
        effect = re.search('effect:\\s*Effect\\.(read|write|destructive)', chunk)
        add(m.group(1), p, title.group(1) if title else '', effect.group(1) if effect else '待自省')
    for m in re.finditer('\\b(?:_spec|_action|_Operation)\\(\\s*[\\\'"]([a-z][a-z0-9_]*(?:\\.[a-z0-9_]+)+)[\\\'"]', s):
        chunk = s[m.end():m.end() + 1000]
        title = re.match("\\s*,\\s*'((?:\\\\'|[^'])*)'", chunk)
        effect = re.search('Effect\\.(read|write|destructive)', chunk)
        add(m.group(1), p, title.group(1).replace("\\'", "'") if title else '', effect.group(1) if effect else '待自省')
rows.pop('task_worker.execute', None)

def put(i, p, e, d):
    rows[i] = [[p, d, e]]

def group(prefix, ops, path, reads='', destructive='', desc=''):
    for x in ops.split():
        put(prefix + x, path, 'read' if x in reads.split() else 'destructive' if x in destructive.split() else 'write', desc or x.replace('_', ' '))
group('task.', 'list get wait cancel', 'packages/nipa_harness/lib/src/tasks/actions.dart', 'list get wait', desc='查询、等待或取消持久任务；以任务回执为完成依据')
group('media.management.', 'bind_batch unbind_batch', 'lib/next/media/management.dart', desc='预览或提交显式身份绑定变更')
group('chat.session.', 'main new list switch', 'lib/next/followups/capability.dart', 'list', desc='选择、创建或列出对话会话')
group('followup.', 'register list cancel', 'lib/next/followups/capability.dart', 'list', desc='登记、查询或取消持久后续')
put('agent.wake', 'lib/next/followups/capability.dart', 'write', '排队唤醒指定或主会话')
put('activity.report', 'lib/next/followups/capability.dart', 'write', '记录带来源的发现')
put('agent.dispatch', 'lib/next/followups/capability.dart', 'write', '派发宿主管理的独立回合')
put('agent.dispatch.report', 'lib/next/followups/capability.dart', 'write', '报告派发回合的工作进展')
group('settings.', 'describe get set reset history', 'lib/next/settings/capability.dart', 'describe get history', desc='读取或修改已注册设置及历史；敏感设置可能需要用户同意')
group('memory.', 'list read edit delete context', 'lib/next/memory/capability.dart', 'list read context', desc='读取或修改个人 harness 记忆；修改检查 revision')
group('download.', 'add set_paused pause resume read select_files import remove delete', 'lib/next/capabilities/download_capability.dart', 'read', 'delete', desc='操作下载任务；删除文件需按回执和授权处理')
group('download.limits.', 'get set', 'lib/next/capabilities/download_capability.dart', 'get', desc='读取或修改下载会话限速')
group('download.', 'preview directories forget_directories', 'lib/next/capabilities/download_metadata_capability.dart', 'preview directories', desc='预览来源或管理最近下载目录')
group('ui.library.', 'sources page items put configure move remove restore', 'lib/next/ui_data/library_capability.dart', 'sources page items', desc='读取或整理本机媒体库展示；不删除源文件')
group('ui.', 'present shelves.put shelves.remove', 'lib/next/ui_data/capability.dart', desc='展示会话卡片或调整首页书架')
put('media.artwork.set', 'lib/next/ui_data/capability.dart', 'write', '设置媒体图片覆盖')
put('media.metadata.ui_facts', 'lib/next/ui_data/capability.dart', 'read', '读取作品资料完整性和来源')
group('media.library.', 'readable refresh status progress', 'lib/next/mesh/library_capability.dart', 'readable refresh status', desc='读取或刷新跨设备目录、解析可读地址或记录进度')
group('media.mesh_files.', 'readable begin chunk finish delete confirm cancel', 'lib/next/mesh/files.dart', 'readable', 'confirm', desc='跨设备读取、暂存传输或预览删除；覆盖或删除需用户同意后由调用方 confirm')
group('mesh.', 'devices invoke invoke_destructive', 'lib/next/mesh/capability.dart', 'devices', 'invoke_destructive', desc='发现或调用经认证的目标设备能力')
group('sync.', 'status configure login enable test run', 'lib/next/media_sources/sync.dart', 'status', desc='查看或管理远端同步；依赖来源配置')
group('subtitle.', 'update remove reset_selection', 'lib/next/subtitles/edit_capability.dart', desc='修改或移除字幕记录、重置选择；文件处理看具体契约')
group('notification.', 'status send list cancel', 'lib/next/system/desktop.dart', 'status list', desc='查询或管理系统通知；依赖宿主')
group('discover.', 'search_config search search_batch trending trending_batch calendar recommendations home refresh', 'lib/next/capabilities/discover_capability.dart', 'search_config search search_batch trending trending_batch calendar home', desc='读取发现、排行或推荐；部分查询需账号和网络')
group('state.', 'describe query', 'lib/next/state/query.dart', 'describe query', desc='说明或查询只读状态视图')
group('danmaku.align_', 'apply keep', 'lib/next/danmaku/capability.dart', desc='按预览应用或保留弹幕对齐')
for a in 'fetch bind prepare attach import'.split():
    put('danmaku.' + a + '_batch', 'lib/next/danmaku/capability.dart', 'write', '批量执行 ' + a + '；逐项回执，非原子')
p = root / 'lib/next/capabilities/playback_inspection.dart'
t = p.read_text()
for m in re.finditer("'([a-z][a-z0-9_]*(?:\\.[a-z0-9_]+)+)'\\s*:\\s*\\(\\s*'((?:\\\\'|[^'])*)'\\s*,\\s*Effect\\.(read|write|destructive)", t):
    put(m.group(1), str(p.relative_to(root)), m.group(3), m.group(2).replace("\\'", "'"))
put('danmaku.set_enabled', 'lib/next/danmaku/capability.dart', 'write', '设置弹幕轨道启用状态；需绑定修订')
put('danmaku.set_dedup', 'lib/next/danmaku/capability.dart', 'write', '设置弹幕显示去重；保留来源缓存')
fix = {'accounts.login': 'write', 'app.restart': 'write', 'app.runtime': 'read', 'db.write': 'write', 'diagnostics.player_log': 'read', 'media.frames': 'read', 'media.identity.bind_batch': 'write', 'media.identity.unbind_batch': 'write', 'media.library.scan_classic': 'write', 'media.management.merge_work': 'write', 'media.metadata.put': 'write', 'media.sources.list': 'read', 'media.sources.search': 'read', 'mesh.delegate': 'write', 'playback.capture': 'write', 'playback.external.danmaku': 'write', 'playback.kernel': 'read', 'playback.kernel_command': 'write', 'playback.set_kernel_properties': 'write', 'playback.state': 'read', 'ui.capture': 'read', 'window.control': 'write'}
for k, v in fix.items():
    if k in rows:
        rows[k][0][2] = v
for k in rows:
    if k.startswith('media.sources.remote_admin.') or k == 'media.sources.addresses':
        rows[k][0][2] = 'write'
t = (root / 'lib/next/danmaku/capability.dart').read_text()
for m in re.finditer("_spec\\(\\s*'(danmaku\\.[a-z_]+)'\\s*,\\s*Effect\\.(read|write|destructive)", t):
    end = t.find('\n  _spec(', m.end())
    end = end if end != -1 else t.find('\n];', m.end())
    strings = re.findall("'((?:\\\\'|[^'\\n]){35,})'", t[m.end():end])
    if strings and m.group(1) in rows:
        rows[m.group(1)][0][1] = strings[-1].replace("\\'", "'")
for k in rows:
    if k.startswith('danmaku.') and (not rows[k][0][1]):
        rows[k][0][1] = '弹幕 ' + k.split('.')[-1].replace('_', ' ') + '；来源及副作用见目标契约'
import hashlib
BASELINE_HASHES = {'lib/next/followups/inbox_capability.dart': '566fb00085f124eddebb5e86bf2e9feb5bca63a6ed33be6b1ff6c3eaed656eb8',
 'lib/next/knowledge/capability.dart': '705ef8725a060aa20504794279f0b433e14288663ee024d17e33477dd9b3c400',
 'lib/next/accounts/capability.dart': '9ef5e384ba221964d8cecd3fa0918286831f51014c80b5c9bdfc4c049c633b1a',
 'lib/next/app_capabilities.dart': '4c9a1eea1af9a09272fcdf074c9de49927bf86a55d77c0d1f9eb3ade68961903',
 'lib/next/body/next_body.dart': 'a4b6fc194df08cbb1573fd731e21effa97f36f213d13993a8d1dfda294e796e9',
 'lib/next/capabilities/app_runtime_capability.dart': '269a8a0bbdd214cd8bff0dece13b780f8b7f7041a7c83b7fa6055be9d2f465aa',
 'lib/next/capabilities/classic_action.dart': '7437bdf0dfda2e98026d3a0983a4d86f6de958aa56bca205880bd5696b2fa7ef',
 'lib/next/capabilities/discover_capability.dart': '9290996a37af6f5430a2faa095b6c9180488459fe2498624d4e6941907094698',
 'lib/next/capabilities/download_capability.dart': '8fb27c9dde90601c9d8e448042b41e85738783f55b23abfa52c45045982e36f5',
 'lib/next/capabilities/download_metadata_capability.dart': '9c55fdf10875cbe97126d4d08e162efbc2fadd9538d32fec4044b35b945ec27a',
 'lib/next/capabilities/download_playback_capability.dart': '56f9b51ac7c8ee83cbc3192f1ff3dd9e27faa3575b55b69c48ec3a650a3eefcf',
 'lib/next/capabilities/family_descriptions.dart': '6d52fbe5f4b0d54fc1a59eef659a6557a5aae7013dcf0dcd1923d982db2672be',
 'lib/next/capabilities/history_capability.dart': '16c32339022d69d1a86120694938820408a879120a22aae2e2cec1862893619f',
 'lib/next/capabilities/kernel_control.dart': '83b08db31481bd3f34bfafb2e0c03b3a903b8b615da1b2a74fde61606f5f70a6',
 'lib/next/capabilities/library_capability.dart': '107685542a32791dbc7424b8a6dcf6d49a0d00a6c9d33ae2cfaccbe7e42a19d2',
 'lib/next/capabilities/local_library_operations.dart': 'f24f0c9e61a0575b3d546b56586762ae9ff012a906fa74362e151c8240698410',
 'lib/next/capabilities/media_frames.dart': '5063f5b53ee527820a677e8dc47ad05d4644487a489405f0783a057c4f3bcf97',
 'lib/next/capabilities/playback_capability.dart': '78c9c6f4457eeda58de24d6a8562c8216f1536f7543d6730c2c591aa18ece782',
 'lib/next/capabilities/playback_controls_capability.dart': 'edd25a427a3fd61fcb498a42dfecb449f245f6e15e835387e9f1138ee55bd5f9',
 'lib/next/capabilities/playback_inspection.dart': 'a97f558f09b9bf8bb690969a1e2fbdca18864099432d211ec5636ad9b0053c42',
 'lib/next/capabilities/ui_capability.dart': 'fc78c6e4e19459be2b0f8f5d988dff9004ae95b45c3d53a5827f39cc00799ca5',
 'lib/next/capabilities/ui_capture.dart': 'd7509fe50aee3c1b276f25d2564ada143236a8d49e103c16f7bcbc37d4832422',
 'lib/next/capabilities/ui_open.dart': '9b34d7e63b864a1d6967eb97d20cd3be36599022fc596b431cec7136ce000e3c',
 'lib/next/capabilities/watched_history.dart': 'f0f66bfa25c5da35ef9c52b092945ae158e27aa9eefe7e7bf45c695a02d541e9',
 'lib/next/danmaku/capability.dart': '79f0e4bcf286a616bc0d7d668f83955b5ae5eb9cf746f3c1c47536c9caef3d8c',
 'lib/next/db/capability.dart': '4c0ccb89a9406d1d435625d698e27855b0ff802833f722ece4467a1cc2819367',
 'lib/next/events/capability.dart': '29862e16e29892241e19385cfb67fdc95d8d6fde7b62e6cddb8bcb5730a0639f',
 'lib/next/followups/capability.dart': 'c78ce3ccc38d9f6167ff10d1bfd7bd08e58d750bb4e5a93b09e050d234187199',
 'lib/next/headless/chat_capability.dart': 'b3512e2ca26b2086f0fc28273331a2b4ad621a65b6e75ee37f08aeb0550b4e80',
 'lib/next/headless/core.dart': 'e67a8e31d430a74dd21ce987711ddddb591e4b71d8033a9dbdfb3a13a57f52d6',
 'lib/next/headless/downloads.dart': 'f01b25716bb35c7e3dc286987832b8898e83db0f4393d52c152f49ea3908e436',
 'lib/next/headless/library_roots.dart': 'cf11e2a49f6a437e031e0d39f544291dc61fe73f27db4cc2036b3f90ab146c44',
 'lib/next/headless/ports.dart': 'f07f7a3cf4b2071f6b7f1578c0047a1bbeb4af070634c481026836b926208d46',
 'lib/next/instance_facts.dart': '0d0f827edf8f0e3ff81706bbfb14e622506600c580439d157e75788d47936f8f',
 'lib/next/media/catalog_capability.dart': 'fb4729d8a35c862346496c23283f132e7c26ecd9e5383f72a674d8b0ffa06ec0',
 'lib/next/media/file_indexing.dart': 'e1d72b823f8923988d451024d2a4899711d9ce4372d958b83b91fa278d89a16d',
 'lib/next/media/management.dart': '65d945b4e79e4e38a82c64bfa93dd89b3d97e69f6132ebdc7588b24341dca6b7',
 'lib/next/media/media_capability.dart': '1f92c7cf328b4d0723bd216eb186f39927a983a80ad177a6be866ef7eb0d7680',
 'lib/next/media/work_merge.dart': '0c2f996d0a7f9ecb7858ecf01b96be470ffda37b2dcdb16980b76f9d6a2566f9',
 'lib/next/media_sources/capability.dart': '298a6d749bdb6f1b23c8a36c5ce2ab92641fc446b31550138673fa74b61a5408',
 'lib/next/media_sources/remote_admin.dart': 'c30bce4b74d697f0da26fb1b7de816dc6143f9b8b87da72a6a4e33bd93550267',
 'lib/next/media_sources/sync.dart': '057f77cf2c894b13905adca4d060d1e6ab4e7da8d4f06c08b59d61025fc8fb3a',
 'lib/next/memory/capability.dart': '75a5b2b9da6f7fceade925cc76a2e776bc9478a4575b2f10786878da237800d1',
 'lib/next/mesh/capability.dart': '7d016bd7ba62cdf8c8567bf926bd1e9a64d27d3441ba2ce8cb3906498cda12a9',
 'lib/next/mesh/delegation.dart': '7083cfde13976088d821b4c66671adc8d0cda91ae5396c13e46cfe1aead4d1e4',
 'lib/next/mesh/files.dart': '88bf2fb55f8d5a6404ca1955e1e430db11e417339dae7335144234992d0bf840',
 'lib/next/mesh/library_capability.dart': 'd9999630399b9aff79bb10f2f14ff2a902b80c572dc6f30edf8ec2f330b37240',
 'lib/next/mesh/runtime.dart': 'b93133e15725a0168abe7b4eeea55ee712bb4cb4436baf783774fcb8a458990b',
 'lib/next/network/capability.dart': 'e90a88e9e5fe88dcd6c4b8e85c39bf2850eda56aa38c0810ecd03e7274f5c98a',
 'lib/next/next_core.dart': 'a2ed645d835ca5ba167a9bba8501b29cb4c380b0cba70843374ffe5f14b01768',
 'lib/next/next_runtime.dart': '66e83c1e0e5ae748a442481bfffda2485ce8c579b6dc85cc6fe439da941121c4',
 'lib/next/player/features/local_operations.dart': '6e1d4e008ebf23f0f62c11abace5e1c10eb355675607d2ee26929b80f362e5b0',
 'lib/next/player/features/operation_specs.dart': '514a6c5049507ee3513bffeb4532d760d03d8f4154a93f00ee680c8af1e3d35a',
 'lib/next/player/ports/session_ports.dart': '57dd00711ffecad900e3d31099d5f82352d45ae443358558d66d023ce500241a',
 'lib/next/programs/repository.dart': 'b36396d06e4b4c7cf0c002252f3a9e027f4ad73866cd5fbef4e4c1687f34309c',
 'lib/next/programs/runtime.dart': 'f3d615ae7438c1c18de2761416146f3fbd89ef4700cf422b17191ec301a5d447',
 'lib/next/settings/capability.dart': 'c6112bb6678f544b7c42ec623c1aa6a101b78d48275f75a75d5d1b9e8fbc65a4',
 'lib/next/settings/consent.dart': 'd9fcf70a6a9362381e7b1176079f5dd6fa75709a00535449d04c727da98c3de6',
 'lib/next/settings/operations.dart': 'b1affc3df109392cb51639aaa96bfdb32bbeab839822b52ac30956cf1de01551',
 'lib/next/settings/prefs.dart': 'af9b70652b7e65d7d9616dbfc818511c177959b63cfaa5d60ba6c60176ae6f0d',
 'lib/next/state/change_history.dart': 'c74d680da0f2b89e0f04a2a3e0c026ad7d49e784aec39d598f9709d571a56006',
 'lib/next/state/query.dart': 'cbe6d8a902be45ee25cd81566fc51f367ed9b9b3dc677e1a421edd5b4426b596',
 'lib/next/subtitles/capability.dart': '8375856deb184041647b6224163f4cae98c261b6344a1246455d7bc9efa036d1',
 'lib/next/subtitles/edit_capability.dart': '7de256174bd60ef21ce620a6459200ffe526903ed8fa68a17d7f3d44454b4fdd',
 'lib/next/system/desktop.dart': 'd7713b9f1bb645970d8b0b671ec55ac9c23e6e4b49fef3a4ebe4c4b78e51be83',
 'lib/next/system/diagnostics.dart': 'cdeca1a0a3bf76134f08adec4abebc39590d50508398b0a8355cc4b33ffb9435',
 'lib/next/system/operation_observations.dart': 'a48a5b031750dad342775fb963b73f256936cae4b02ad951b86b8ca28960fa80',
 'lib/next/system/runtime_diagnostics.dart': '9984e5a080c08e77349c43c328b2e52b55cd3440bacf75dde58d8dd248d03350',
 'lib/next/system/storage.dart': '8d6d251c87b8b8dc35c1dd8826a046a3cad0fe5190cbbf1cd18f13fb94b6f3bc',
 'lib/next/tasks/resources.dart': '1d0484e666c5f93b017b9898b73534b69a9c6e9ffcf9bcdc0ae1922dff8ba750',
 'lib/next/tasks/user_consent.dart': 'b570b5a457943c77cb1ac356394321562c80ae1567996005779686ccbe9f3b3f',
 'lib/next/ui_data/capability.dart': 'afb364ba2e57a7e504d81ba72df2010a21caa6ee93ad69b9d4670295d2c11c74',
 'lib/next/ui_data/library_capability.dart': '6d1f854d5afb865855d1e1f54aa499d5806044410b2348a29cc478e336931124',
 'lib/security/credential_capability.dart': '26bc1852bc98ef1c4c21446b165bfb0764bdb7c763fbd16355079ebbd03f32ac',
 'packages/nipa_harness/lib/src/action.dart': 'b80ccb05cb5eb0143290d6750ec8b4557da08511c222dfff06f929d329efcb55',
 'packages/nipa_harness/lib/src/tasks/actions.dart': '41ddb4650c62b8045c11cf90c349a17dc93dbaa7c66b6b3fcf243f3551e310ce',
 'packages/nipa_harness/lib/src/tasks/engine.dart': '5c43659484aaa994fc3f8be416fa01f144bc8bb10423959ccfdb8f09f471130d'}
current_files = {str(p.relative_to(root)) for p in paths if '/ui/dev/' not in str(p) and any((t in p.read_text() for t in ('ActionSpec(', 'extends Action<', 'implements Capability')))}
current_files.update(['lib/next/next_core.dart', 'lib/next/next_runtime.dart', 'lib/next/headless/core.dart', 'lib/next/headless/ports.dart', 'lib/next/body/next_body.dart', 'lib/next/mesh/runtime.dart'])
drift = []
for name in sorted(current_files | set(BASELINE_HASHES)):
    file = root / name
    digest = hashlib.sha256(file.read_bytes()).hexdigest() if file.exists() else None
    if digest != BASELINE_HASHES.get(name):
        drift.append(name)
if drift:
    print('Registration source changed or unknown; review dynamic templates: ' + ', '.join(drift))
reference = (root / 'docs/next/development/ACTION_REFERENCE.md').read_text()
documented = set(re.findall('^\\| `([a-z][a-z0-9_.]+)` \\|', reference, re.M))
expected = set(rows)
missing, extra = (sorted(expected - documented), sorted(documented - expected))
for heading, items in [('Missing', missing), ('Unrecognized', extra)]:
    if items:
        print(heading + ': ' + ', '.join(items))
print(f'Source candidates: {len(expected)}; documented IDs: {len(documented)}')
raise SystemExit(bool(missing or extra or drift))
