# 阶段 V：凭据保险库

## 完成了什么

`lib/security/credential_vault.dart` 定义 namespace + key 的 `CredentialRef` 和
read/write/delete 接口；`lib/next/credentials.dart` 与媒体接口导出同一类型。
NextCore 暴露宿主保险库和 `credentials.status` Action。秘密输入不开放给 Agent。

桌面经 FRB 2.12.0 调用 Rust `VaultService` / keyring 3.6.3；macOS 使用本机
Keychain，Windows 使用 Credential Manager，Linux 使用 Secret Service。
移动、电视、鸿蒙和 Web 使用现有偏好存储适配层，保留原有账号和连接存储。

## 决策

启动时迁移，读旧值 → 写保险库 → 回读逐字比较 → 用引用替换原明文。
连接列表与文件按条目迁移；一项失败不撤销已成功的项，也不删除失败项。
失败原值仍由宿主读取，下一次启动重试。原因只记录安全错误码/异常类型，
记录在 `vault_migration_failures_v1`、诊断日志和用户可见提示中。

| 已核实的源 | 宿主读写位置 | 验证方式 |
|---|---|---|
| `dandanplay_token` | dandanplay_service_io/stub、search_service、trending_bangumi_service；auto_sync 清理 | 标量迁移、原值读取、失败保留、重试、退出删除；备份导出/恢复测试 |
| `bangumi_access_token` | bangumi_api_service；auto_sync 清理 | 同上，另测新设备恢复后登录态为 false |
| `dandanplay_remote_api_token` | dandanplay_remote_service | 标量迁移和回读；全量备份只导出引用 |
| `incremental_sync_webdav_password` | auto_sync_settings → auto_sync_service | 标量迁移与读写；偏好备份只导出引用 |
| `webdav_connections[].password` | webdav_service | 每项迁移，成功项替换引用、失败项保留；宿主还原连接；删除连接后删除条目；备份过滤 |
| `smb_connections[].password` | smb_service | 每项迁移与宿主还原、备份过滤；ID 缺失时引用使用摘要，不直接包含 URL |
| `emby_access_token`、`jellyfin_access_token` | media_server_service_base | 标量迁移与统一读写；账号登录和请求继续使用内存 token |
| `server_profiles[].accessToken` | multi_address_server_service；媒体服务和备份恢复 | 每项迁移与宿主还原；profile 和 serverAccounts 两处备份过滤 |
| `spoiler_ai_api_key` | video_player_state_subtitles → danmaku_spoiler_filter_service | 标量迁移、宿主读取、偏好备份过滤 |
| `plugin_text_setting_<pluginId>::<entryId>`、`plugin_<pluginId>_<key>` 的字符串 | plugin_service | 全部字符串入库，保持插件内存 API；插件伪造其他命名空间引用无法读取账号秘密 |
| `next/credentials.json` 的字符串项（含 tmdb） | VaultCredentialResolver / media_runtime | 逐项迁移、回读一致、失败项保留、重试；文件只保留引用；缺少配置返回 unavailable |
| `next/endpoint.json.token` | agent_endpoint | 迁移同一 token，端点重启后鉴权仍可用；文件只保存引用 |
| 历史 `dandanplay_app_secret` | 现代码不再使用，旧初始化会直接清理 | 纳入标量迁移；桌面只有回读成功才去除明文，失败时不直接清理 |
| 旧日志、journal 与 `incremental_sync/*.index.json` 中的秘密 | credential_diagnostics_migration | 清理哨兵秘密、保留公开字段；旧索引强制重建；失败保留原文件并报告 |

用户名、昵称、Bangumi 用户资料、绑定信息、遥控信任记录和设备 ID 在已检查代码中
不包含认证秘密，继续保留元数据。插件没有秘密类型声明，因此字符串存储整体入库。
`next/workspace/.codex/config.toml` 的回环 MCP token 按任务书例外继续保留。

全量备份与增量同步写出引用。旧远端状态、缓存和快照压缩也经过过滤，避免把
旧明文重新上传；历史播放 URL 的认证信息整串入库，以字符串形式的引用兼容
现有备份 codec。恢复只在接收宿主解析引用；新设备缺少对应凭据时显示重新登录/
输入密码提示。同一设备继续使用本机凭据。用户已有备份档案不被自动改写。

输入 schema 新增可选 `secret` 标记（默认 false，JSON Schema 输出 writeOnly/x-secret）。
Harness 在交给 observer 前替换秘密字段；嵌套数组、无效输入和认证 URL 都过滤。
未发生过滤时保留输入对象身份。invocation/diagnostic 引用是审计标记，不额外存储
输入秘密副本。宿主 print/debugPrint、日志收集及同步错误持久化经过秘密过滤。

Linux 缺少 Secret Service 时选择显式失败，不新增明文回落。旧凭据保留可用，
新写入失败由持续提示和 `credentials.status` 展示。移动等平台的后续 native backend
可替换 `CredentialVault`，本期不迁移其现有偏好凭据。

## 验收命令与真实输出

Flutter/Dart 均使用 `~/development/flutter-3.44.6/bin/`，未运行 pub get。

- `flutter test --no-pub test/security test/next`：`+250: All tests passed!`
- `cd packages/nipa_harness && dart test`：`+86: All tests passed!`
- `flutter analyze --no-pub lib/security lib/next packages/nipa_harness/lib test/security lib/services/auto_sync_service.dart lib/utils/auto_sync_settings.dart lib/services/full_backup_service.dart`：`No issues found!`
- `cd rust && cargo build`：`Finished dev profile`，退出 0（既有警告仍在）。
- `cd rust && cargo test`：`123 passed; 2 failed`。两项失败均依赖 `/Users/retr0/Documents/program_works/NipaPlay-Reload/` 下的个人弹幕 JSON，仓库没有这些文件。
- `cargo test -- --skip test_real_danmaku_local_file --skip test_real_danmaku_no_top_overlap`：123 单元测试、2 command_channel、15 motion_clock 全通过。
- `flutter build macos --debug --no-pub`：`✓ Built build/macos/Build/Products/Debug/NipaPlay.app`。
- 临时 Dart 入口放在仓库外 `/tmp`，以 `flutter build macos --debug --no-pub --target ...` 构建 NipaPlay bundle，调用临时 Rust 自检桥后退出。输出：`NIPAPLAY_VAULT_BUNDLE_ROUNDTRIP: write/read/delete/missing=true`，退出 0。随后删除临时 Dart/Rust 探针、重新生成桥并恢复主入口构建；最终 API 只有 read/write/delete。

真机测试仅发生在 NipaPlay bundle 内。测试服务名为
`com.nipaplay.credential-vault.self-test`，账户名含进程 ID 和时间戳；Rust 在返回前
删除测试项并再次读取确认缺失，失败路径也尝试删除。验证用临时代码已移除。未进行跨程序访问或签名轮换实验。

`codesign -dvv -r- --entitlements :- NipaPlay.app` 确认调试构建启用
`com.apple.security.app-sandbox=true`、`Signature=adhoc`、无 TeamIdentifier，指定需求
绑定 cdhash。本 bundle 使用本应用钥匙串条目无需新增共享 access group；往返测试未出现
授权密码框。代码身份/签名改变时，旧条目的信任要求可能不再匹配，会触发授权框；
稳定正式签名应保持签名身份连续。该结论依据签名要求与钥匙串 ACL 语义，未做轮换实验。

## 问题

完整 cargo test 门禁仍被两项仓库外个人文件测试阻塞，需要主控决定是否为它们提供
可提交的离线夹具或改成手动测试。本阶段没有修改这些无关弹幕测试。
Windows/Linux 真实系统存储和恢复到第二台设备的端到端验收需对应平台补测；本机仅
验证 macOS 原生 backend，其余平台的配置与失败路径经代码检查/模拟测试验证。
Windows/Linux 的同用户进程权限由系统决定，不能把系统保险库等同于进程隔离。

未提交 commit，未 push，未读取指定的参考实现分支。
