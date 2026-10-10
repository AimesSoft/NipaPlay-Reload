# 设置与保险库合并验收（2026-10-11）

1. 完成了什么

在 `next/capability-layer` 依次执行 `git merge --no-ff next/settings` 与
`git merge --no-ff next/mesh-vault`，由实现者完成两个合并提交，均附
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。未 push，未运行 pub get。

设置注册表、Classic 设置来源记录、媒体按需索引、本地与在线弹幕能力以及
凭据保险库共同保留。NextCore 组合设置与保险库能力，共享原有引擎和数据库。
`credentials.status` 已加入覆盖率基线；运行时与基线均为 57 个 Action、126 个设置。

2. 决策

每处文本冲突及解决方式如下：

| 合并 | 文件 | 解决方式 |
|---|---|---|
| settings | `lib/next/README.md` | Core 暴露列表同时保留 danmaku 与 settings；说明设置迁移固定追加为 v4。 |
| settings | `lib/next/next_core.dart` | 先接入设置注册表和路径授权，再创建弹幕运行时；保留 `authorizeLocalFile: media.service.authorizedPath`。 |
| settings | `lib/next/next_runtime.dart` | 同时保留媒体文件索引与设置绑定导入，继续使用原文件索引包装和设置可见性规则。 |
| mesh-vault | `lib/services/dandanplay_service_io.dart` | 同时保留弹幕 comments 解析与 CredentialStore 导入，使弹幕解析及保险库账号读写共同生效。 |
| mesh-vault | `lib/services/dandanplay_service_stub.dart` | 同上，保留 Web 的弹幕解析和凭据后端适配。 |

整合决策：

- 数据库只保留 v1 任务 → v2 媒体身份 → v3 弹幕 → v4 设置的单一迁移序列；保险库没有新增 SQL 表。新增行为测试覆盖新库、v1/v2/v3 升级、v4 重开及设置记录持久化；原有测试继续验证旧任务和媒体数据保留。
- 禁止清单复用保险库的标量键和秘密键判定，同时显式拒绝含密码/token 的连接列表、TMDB 和端点凭据。插件字符串存储及保险库后端物理键同样拒绝。测试验证这些键不能注册，且 settings.get/set/reset 返回 not_found。
- 剧透 AI 密钥读写保留 CredentialStore 路径；公开模型等参数仍经 SettingsAccess 记录来源。共存测试验证偏好里仅有 CredentialRef、秘密在保险库中可回读、设置历史不含密钥。
- 设置测试注入内存保险库并恢复宿主实例，避免往返测试触碰本机钥匙串。
- 对两份冲突服务文件做最小 lint 修正（debugPrint、插值、const、去掉无效非空断言），通过用户要求的 Classic 文件分析；不改账号请求和弹幕解析语义。
- macOS 构建自动改写的 Podfile.lock 已恢复，不将本机依赖缓存差异纳入合并。

3. 验收命令与真实输出

所有 Flutter/Dart 命令使用 `~/development/flutter-3.44.6/bin/`。以下为最终源代码的验收结果，全部退出 0。

```sh
cd packages/nipa_harness
~/development/flutter-3.44.6/bin/dart test
# 00:00 +86: All tests passed!
```

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub \
  lib/next test/next lib/security test/security \
  lib/services/dandanplay_service_io.dart \
  lib/services/dandanplay_service_stub.dart lib/utils/video_player_state.dart
# No issues found! (ran in 3.7s)
```

播放器的 part 文件随 `lib/utils/video_player_state.dart` 所属库分析。

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub --reporter expanded \
  test/next test/security test/danmaku_track_*_test.dart test/torrent_*.dart \
  test/*setting*_test.dart test/settings \
  test/dandanplay_login_notice_test.dart test/dandanplay_http_client_test.dart \
  test/utils/dandanplay_auth_test.dart test/large_screen_player_remote_test.dart
# 00:11 +381: All tests passed!
```

```sh
cd rust
cargo build
# Finished `dev` profile [unoptimized + debuginfo] target(s) in 42.04s
```

Rust 构建保留 7 条既有编译警告，另有 ndk-sys 版本元数据提示。

```sh
~/development/flutter-3.44.6/bin/flutter build macos --debug --no-pub
# ✓ Built build/macos/Build/Products/Debug/NipaPlay.app
```

构建保留插件 Swift Package Manager 迁移提示及两条脚本输出依赖警告。
覆盖率导出测试输出 `Capability coverage: 57 actions, 126 settings.`，并通过；
逐项核对导出的运行时目录和基线，全部键、effect、scope 一致。`git diff --check` 通过。

4. 问题

本次指定验收无阻塞项。未执行完整仓库 Flutter/Rust 测试、Windows/Linux 构建或
真实账号及第二台设备端到端验收；`QUALITY_GATE.md` 中合回 main 前的独立整体审查、
全仓门禁和真实环境验证仍由主控安排。本报告只证明上述合并验收范围。
