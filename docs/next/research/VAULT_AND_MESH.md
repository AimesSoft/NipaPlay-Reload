# NipaPlay Next：凭据保险库与 Mesh 调研

> 调研日期：2026-10-10
> 范围：工作区源码、本机依赖缓存（`~/.pub-cache`、`~/.cargo/registry`）、Dart SDK 与本机可读的官方文档
> 证据约定：仓库相对路径 `file:line`；依赖源码写绝对缓存路径；无法从源码确证的行为标注为**推测**或**待验证**
> 前置文档：`docs/next/DESIGN.md` §2.3、§3、§9 第 3/6 项；`docs/next/research/LAN_SECURITY.md` §6–§8

---

## 0. 结论摘要

1. **当前明文凭据远不止 SharedPreferences 的几个键。** 除 `dandanplay_token`、`bangumi_access_token`、WebDAV/SMB 密码、媒体服务器 `access_token`、AI API key 外，还有 `next/endpoint.json`、`next/workspace/.codex/config.toml`、`next/credentials.json`、`server_profiles`、插件存储键，以及 `journal.jsonl` 这类可能写入输入的回执日志。迁移到保险库是一次跨领域改动，不是替换一个存储类。
2. **保险库推荐“Rust FRB 桥 + 平台原生后端”作为唯一写入/读取实现，Dart 只持有 `CredentialRef`。** 纯 Dart 插件方案在 tvOS、HarmonyOS 覆盖不齐；`flutter_secure_storage_tvos` 只覆盖 tvOS 且依赖主插件 10.x（本机缓存证据），`flutter_secure_storage` 主插件与 OHOS 实现在本机缓存中不存在；`keyring` 类 crate 的 Windows/Linux/macOS 后端成熟，但 Android/iOS/tvOS/OHOS 需要平台专用后端，因此推荐“Dart API + Rust keyring 抽象 + 各平台后端实现”，而非直接依赖某个 Flutter 插件。
3. **设备身份用 Ed25519，但传输层建议 TLS 1.3 且证书绑定设备公钥，而不是自行拼装 Noise。** Dart `SecureSocket` 提供 `SecurityContext.setTrustedCertificatesBytes`、`useCertificateChainBytes`、`usePrivateKeyBytes`、`onBadCertificate`、`peerCertificate.pem`，足以做“证书链由服务器签名、客户端按已登记公钥校验”的方案；Noise 在 Dart 侧没有官方实现，Rust 侧 `snow` 不在现有依赖里，落地成本更高。若必须跨平台统一密码学，可在 Rust 侧实现 Noise，但这不是最小版本首选。
4. **协调服务应作为独立二进制，而不是塞进 `dandanplay-gateway`。** 现有网关是单一职责的透明反代，进程内没有数据库、没有账户表、没有设备表；把它扩成协调服务会同时承担高流量上游代理与低频控制面，违背既定“服务器只做控制面”的方向。复用方式应是**复用其令牌验证函数**（`validate_account_token`），而不是复用进程。
5. **Mesh 最小版应只覆盖“Mac Agent → 工位机 Harness”的单向调用。** Action 面建议先只开 `task.list/get/wait/cancel` 与 `download.add/pause/resume/remove/delete`，以 `mesh.devices`、`mesh.invoke` 暴露；`download.delete` 保持 `destructive`，默认要求本机确认。
6. **LAN_SECURITY 第 6 节 A 档修复与 Mesh 不冲突，但顺序上应先做 A1/A3/A5/A6，再做 B。** Mesh 上线后，旧 `/api` 中“账号副作用、凭据读取、任意路径读取、代理”类接口应只在安全通道上提供；媒体流接口应改为资源票据；`/api/info` 与 UDP 发现保留为无秘密的线索接口。

---

## 1. 现有凭据盘点

### 1.1 SharedPreferences 中的秘密

| 凭据 | 键 | 写入位置 | 读取/使用位置 | 是否进入备份 | 迁移影响 |
|---|---|---|---|---|---|
| 弹弹play 账号 token | `dandanplay_token` | `lib/services/dandanplay_service_io.dart:273`、`:385`；stub `lib/services/dandanplay_service_stub.dart:320` | `lib/services/dandanplay_service_io.dart:186`、`:255`、`:90-95`；`lib/services/search_service.dart:287`；`lib/services/trending_bangumi_service.dart:171` | 是，`lib/services/full_backup_service.dart:431` | 读写点最多，涉及登录、续期、搜索、热门、媒体元数据 |
| 弹弹play 用户名/昵称/登录态/续期时间/绑定信息 | `dandanplay_username`、`dandanplay_screenname`、`dandanplay_logged_in`、`last_token_renew_time`、`dandanplay_linked_bangumi_account`、`dandanplay_login_timestamp` | `lib/services/dandanplay_service_io.dart:274-280`、`:387-390`；stub `:251-253` | `lib/services/dandanplay_service_io.dart:179-182`、`:2715`；stub `:2578` | 是，`lib/services/full_backup_service.dart:432-448` | 用户名可留明文；绑定信息可能含账号标识，建议一并入保险库 |
| Bangumi 访问令牌 | `bangumi_access_token` | `lib/services/bangumi_api_service.dart:252` | 同上 `:23`、`:245`；`lib/services/auto_sync_service.dart:911` 清理 | 是，`lib/services/full_backup_service.dart:457` | 独立账号路径，需单独迁移 |
| Bangumi 用户信息 | `bangumi_user_info` | `lib/services/bangumi_api_service.dart:253` | 同上 `:24`、`:246` | 是，`lib/services/full_backup_service.dart:458-462` | 含用户资料，未必是秘密，但含账号标识 |
| 弹弹play 远程服务 API token | `dandanplay_remote_api_token` | `lib/services/dandanplay_remote_service.dart:374` | 同上 `:59`、`:326-327`、`:381-386` | 是，`lib/services/full_backup_service.dart:275` | 该 token 还会拼进流 URL 查询串，迁移时要同时改 URL 生成 |
| WebDAV 连接（含密码） | `webdav_connections` | `lib/services/webdav_service.dart:251` | 同上 `:214`、`:458-459`、`:1017` | 是，`lib/services/full_backup_service.dart:250-252` | 连接列表整体 JSON，需拆分 secret 与元数据 |
| SMB 连接（含密码） | `smb_connections` | `lib/services/smb_service.dart:226-229` | 同上 `:206`、`:343-344`、`:520` | 是，`lib/services/full_backup_service.dart:261-262` | 同上 |
| 增量同步 WebDAV 密码 | `incremental_sync_webdav_password` | `lib/utils/auto_sync_settings.dart:143` | 同上 `:92-95`；`lib/services/auto_sync_service.dart:255` | 是，`lib/utils/auto_sync_settings.dart:35` | 与普通 WebDAV 连接是两套配置，易漏 |
| 媒体服务器（Emby/Jellyfin）`access_token` | `emby_access_token`、`jellyfin_access_token` | `lib/services/media_server_service_base.dart:444` | 同上 `:241`、`:818-819`；播放 URL `lib/services/jellyfin_service.dart:1330`、`lib/services/emby_service.dart:1427` | 是，通过 `server_profiles` 与 `serverAccounts`，`lib/services/full_backup_service.dart:477`、`:1144` | token 还出现在播放/字幕 URL 查询参数里 |
| 媒体服务器用户名/URL/用户 ID | `emby_server_url`、`emby_username`、`emby_user_id`、`jellyfin_*` 同名前缀 | `lib/services/media_server_service_base.dart:442-445` | 同上 `:239-242` | 是 | URL/用户名可留；token 必须迁出 |
| 服务器 profile 列表（含 accessToken） | `server_profiles` | `lib/services/multi_address_server_service.dart:55` | 同上 `:34`；`lib/services/full_backup_service.dart:311`、`:1144` | 是 | `ServerProfile.toJson()` 直接序列化 `accessToken`：`lib/models/server_profile_model.dart:144` |
| AI 防剧透 API key | `spoiler_ai_api_key` | `lib/utils/video_player_state/video_player_state_subtitles.dart:494` | 同上 `:442`；使用 `lib/utils/video_player_state/video_player_state_danmaku.dart:1187` | 是，作为普通设置键（未被排除列表过滤，`lib/services/full_backup_service.dart:170-185`） | 建议迁移并改为“已配置/未配置”状态 |
| 插件文本设置与插件存储 | `plugin_text_setting_<pluginId>::<entryId>`、`plugin_<pluginId>_<key>` | `lib/plugins/plugin_service.dart:180`、`:608` | 同上 `:216`、`:615` | 是，属于普通设置键 | 无法静态判断哪些值含秘密；建议增加“秘密类型”声明 |
| 遥控信任记录与 clientId | `remote_control_trusted_devices`、`remote_control_client_id` | `lib/services/remote_control_settings.dart:72`、`:103` | 同上 `:78`、`:65`；`lib/services/remote_control_auth_manager.dart:26`、`:44` | 是，属于普通设置键 | 信任记录不含私钥，但迁移到设备身份后应改为公钥信任表 |
| 媒体服务器生成/自定义设备 ID | `media_server_generated_device_id`、`media_server_custom_device_id` | `lib/services/media_server_device_id_service.dart:68`、`:85` | 同上 `:42`、`:78` | 是 | 不是长期秘密，但属于设备身份，建议统一由设备身份模块管理 |

### 1.2 文件中的秘密

| 文件 | 内容 | 写入位置 | 读取/使用位置 | 权限处理 | 迁移影响 |
|---|---|---|---|---|---|
| `<AppSupport>/next/endpoint.json` | MCP Bearer token | `lib/next/agent_endpoint.dart:82` | 同上 `:59-60`；注入 `lib/next/agent_workspace.dart:21` | 非 Windows 用 `chmod 600`，Windows 未限制：`lib/next/agent_endpoint.dart:68-83` | 必须迁入保险库；否则任何同用户进程可读 |
| `<AppSupport>/next/workspace/.codex/config.toml` | 同一 MCP Bearer token 明文写入 `http_headers` | `lib/next/agent_workspace.dart:18-33` | Codex 读取该文件 | 无额外权限控制 | 这是最直接的“Agent 可读秘密”路径，DESIGN §9 第 3 项已点明 |
| `<AppSupport>/next/credentials.json` | 元数据供应商秘密（当前是 TMDB `api_key`） | `lib/next/media/provider_transport.dart:26` | 同上 `:66-81`；`lib/next/media/media_runtime.dart:34-47` | 非 Windows `chmod 600`；Windows 用 PowerShell ACL：`lib/next/media/provider_transport.dart:32-60` | 设计上已用 `CredentialRef` 隔离（`lib/next/media/metadata_provider.dart:93-101`），是迁移的现成接口 |
| `<AppSupport>/next/device.json` | 当前仅 `deviceId`，非秘密 | `lib/next/tasks/device_identity.dart:21` | 同上 `:10`；`lib/next/next_core.dart:52` | 无 | 未来 Ed25519 私钥不能沿用该文件 |
| `<AppSupport>/next/journal.jsonl` | Harness 调用回执日志 | `lib/next/next_runtime.dart:81` | 同上 | 无 | 若 Action 输入含路径/token，会形成旁路泄露，需过滤 |
| `next.db` | 任务快照与输入 | `lib/next/tasks/sqlite_job_store.dart`；`lib/next/next_database.dart` | `NextCore` 打开 | 无 | `download.add` 的 `source` 可能含带凭据的 URL |

### 1.3 迁移到保险库的影响面

- **调用点分散。** `dandanplay_token` 在登录、续期、搜索、热门、媒体元数据至少 5 处读取；WebDAV/SMB 密码在连接、目录浏览、播放 URL 至少 3 处使用。
- **备份语义会改变。** 目前全量备份显式导出 `dandanplay.token`、`bangumi.accessToken`、`dandanplayRemote.apiToken`、`serverAccounts[].accessToken`、`webdavConnections[].password`、`smbConnections[].password`（`lib/services/full_backup_service.dart:431`、`:457`、`:275`、`:477`、`:251`、`:262`）。迁入钥匙串后必须决定：备份是**不导出秘密**，还是导出“需要重新输入”的占位符。
- **平台差异会暴露。** 当前 `endpoint.json` 在 Windows 没有 ACL 限制（`lib/next/agent_endpoint.dart:70` 只在非 Windows 执行 `chmod`），`credentials.json` 反而做了 Windows ACL。迁移应统一到同一保险库接口。
- **Agent 可读性是真问题。** `writeAgentWorkspace` 把 token 明文写入 Agent 工作区内的 `config.toml`（`lib/next/agent_workspace.dart:21`），与 DESIGN §2.3“凭据不出现在 Agent 可读的位置”直接冲突。**这是必须先于 Next Shell 解决的问题。**

---

## 2. 保险库实现选型

### 2.1 各平台可用的原生后端

| 平台 | 原生安全存储 | 所需 entitlement / 权限 | 沙箱下行为 | 同用户其他进程 | 备份与同步 |
|---|---|---|---|---|---|
| macOS | Keychain（`kSecClassGenericPassword`，可选 Data Protection Keychain） | App Sandbox 下需要 `keychain-access-groups`；本仓库当前 entitlements 只有 app-sandbox、网络、文件、相机，见 `macos/Runner/Release.entitlements:5-21` | 沙箱内可访问本应用 Keychain 项；`keychain-access-groups` 可共享 | **默认不可读**；同用户其他进程需代码签名与 access group 授权 | iCloud Keychain 取决于 `kSecAttrSynchronizable`；默认本地 |
| Windows | Credential Manager（`wincred`）或 DPAPI | 无额外 manifest 权限 | 无沙箱概念，按用户加密 | **同用户进程可读**；DPAPI 默认按当前用户解密 | 通常不随 Microsoft 账户同步；`Credential Roaming` 需域策略 |
| Linux | Secret Service（GNOME Keyring / KWallet）或内核 keyring | 需要 `libsecret`/D-Bus；无 D-Bus 的服务器环境不可用 | 无沙箱 | 取决于 Secret Service 解锁状态；同会话进程可能可读 | 由桌面环境同步决定，通常不同步 |
| iOS | Keychain | 无需额外 entitlement（除非 App Group / 共享 Keychain） | 沙箱内可访问 | **默认不可读**；同 Team 且共享 access group 才可读 | 可设 `kSecAttrSynchronizable` 随 iCloud Keychain 同步 |
| Android | Keystore + EncryptedSharedPreferences | 无需额外权限 | 沙箱内可访问 | **默认不可读**；同 UID 或 root 可读 | 随 Auto Backup 取决于 `dataExtractionRules`；Keystore 密钥通常不备份 |
| HarmonyOS (ohos) | HUKS（HarmonyOS Universal KeyStore） | 需要 `ohos.permission.INTERNET` 之外的**无额外权限**；HUKS 是系统能力 | 沙箱内可访问 | **默认不可读** | 取决于系统备份策略，需实测 |
| tvOS | Keychain | 无需额外 entitlement | 沙箱内可访问 | **默认不可读** | 同 iOS，可设 synchronizable |

> 平台侧行为中，macOS/iOS/tvOS 的 Keychain 与 Android Keystore 的隔离性有充分官方文档依据；**Windows Credential Manager 与 Linux Secret Service 的“同用户其他进程可读”是平台语义，本调研未在本仓库运行时验证**。

### 2.2 三种方案对比

#### 方案 A：Flutter 插件（`flutter_secure_storage` 及各平台实现）

- **本机缓存事实：** 主插件 `flutter_secure_storage` 与 OHOS 实现**不在本机 pub 缓存**中；仅存在 `flutter_secure_storage_tvos`：
  `~/.pub-cache/git/plugins-79dc1ac13b94d593e2361bf10b5ed8bdd225d3db/packages/flutter_secure_storage_tvos/pubspec.yaml:1-3`
- tvOS 实现 README 明确：支持 Keychain-backed read/write/delete；**tvOS 无生物识别**，相关标志是 no-op：
  `.../flutter_secure_storage_tvos/README.md:11-25`
- tvOS 实现依赖 `flutter_secure_storage: ^10.x`（README `:11`），而本仓库 `pubspec.yaml` 当前没有该依赖，`pubspec.lock` 也没有 `flutter_secure_storage` 条目（`rg` 无命中）。
- **HarmonyOS：** 本机缓存无 `flutter_secure_storage_ohos`；现有 OHOS 适配插件走 `pubspec_overrides.ohos.yaml` 的 Git 源（例如 `shared_preferences`、`sqflite`），说明 OHOS 依赖需要专门 fork。**推测：** 若要上 OHOS，需自行 fork 或实现 HUKS 平台通道。
- **结论：** 插件方案在 macOS/Windows/Linux/iOS/Android 可行，在 tvOS 有可用 fork，在 HarmonyOS 需要额外工作；且它把“Rust 侧也需要凭据”的场景排除在外（Rust 进程无法直接调用 Dart 插件，除非反向走 FRB）。

#### 方案 B：现有 Rust FRB 桥引入 keyring 类 crate

- 本仓库已有 `rust_lib_nipaplay` 与 FRB 2.12.0：`rust/Cargo.toml:1-10`、`pubspec.yaml` 中 `flutter_rust_bridge: 2.12.0`。
- 本机 cargo 缓存中已有 `security-framework`、`rustls`、`ring`、`zeroize`，但没有 `keyring` crate：
  `~/.cargo/registry/src/*/` 中存在 `security-framework-2.11.1`、`rustls-0.23.x`、`ring-0.17.14`、`zeroize-1.8.2`；`rg keyring` 无命中。
- **优点：** Dart 与 Rust 共用同一凭据读取路径；Rust 侧做 TLS/Noise、签名时无需把秘密再传回 Dart；可以用 `zeroize` 控制内存生命周期。
- **缺点：** `keyring` crate 的 Android/iOS/tvOS/OHOS 后端并不统一。**推测：** 需要为移动端与 OHOS 分别写 Keystore/HUKS 后端，或让 Rust 通过 JNI/FFI 调平台 API；这会扩大 Rust 侧平台分支。
- **所需权限：** 桌面端无额外权限；Android 需要 JNI 到 Keystore；iOS/tvOS 需要 Security.framework；OHOS 需要 HUKS native API。**待验证：** OHOS 上 Rust 调 HUKS 的可行路径。

#### 方案 C：平台通道自行实现

- **优点：** 每个平台可用最合适的原生 API，entitlement 控制最精确。
- **缺点：** 7 个平台 × 读/写/删/列举 = 大量样板；tvOS 与 OHOS 的插件注册本身需要 fork（本仓库已有 `pubspec_overrides.tvos.yaml`、`pubspec_overrides.ohos.yaml` 的先例）。
- **结论：** 不建议作为主方案，但可作为方案 B 的兜底：Dart 定义 `Vault` 接口，Rust 提供桌面实现，平台通道提供移动端实现。

### 2.3 推荐方案

**推荐：Dart 侧 `CredentialVault` 接口 + Rust FRB 桥 `vault_*` + 平台后端适配。**

```text
Dart (UI/Action)
  └─ CredentialVault (Dart interface, 只暴露 CredentialRef)
       └─ FRB → Rust VaultService
            ├─ macOS/iOS/tvOS: Security.framework (Keychain)
            ├─ Windows: Credential Manager / DPAPI
            ├─ Linux: Secret Service (libsecret) + 无 D-Bus 时降级到 0600 文件并明确告警
            ├─ Android: JNI → Keystore/EncryptedSharedPreferences
            └─ OHOS: NAPI/HUKS 适配
```

**理由：**

1. 与 DESIGN §2.3 的“凭据只以引用形式存在”一致；`CredentialRef` 已存在（`lib/next/media/metadata_provider.dart:93-101`），可直接推广。
2. 未来 Mesh 的设备私钥、TLS 客户端证书都要在 Rust 侧用于签名/握手，放在 Rust 可避免秘密跨 FFI 边界来回传递。
3. tvOS 有现成的 `flutter_secure_storage_tvos` 可参考实现；OHOS 无论如何都需要适配层，放在 Rust 侧比散落在 Dart 插件更容易统一。
4. 备份行为可在 Dart 侧显式控制：备份文件只写 `credentialRef`，不写值。

**所需 entitlement / 权限清单：**

- macOS：`keychain-access-groups`（若需与 Agent 子进程共享）；当前 entitlements 需新增，见 `macos/Runner/Release.entitlements:5-21`。
- iOS/tvOS：无需额外 entitlement；若用 App Group 共享则需 `keychain-access-groups`。
- Android：无需额外权限；需在 `AndroidManifest.xml` 保持现有 `INTERNET` 等权限（`android/app/src/main/AndroidManifest.xml:3-17`）。
- OHOS：HUKS 无额外权限；网络仍需现有 `ohos.permission.INTERNET`（`ohos/entry/src/main/module.json5:42`）。
- Linux：需要 `libsecret` 与可用的 Secret Service；无桌面会话时应显式失败或降级。
- Windows：无额外权限。

### 2.4 Agent 进程能否读取

- **macOS/iOS/tvOS Keychain：** 默认不能。除非同一 access group 且代码签名允许。**推测：** Codex App Server 若以独立进程运行，需要用共享 access group 或由 NipaPlay 主进程代理读取，不能直接给子进程 Keychain 权限。
- **Windows Credential Manager：** 同用户的其他进程**可以**读取，因此 Windows 上“保险库”不等于“Agent 不可读”。若要隔离 Agent，必须让 Agent 只能通过 Harness 的 `CredentialRef` 间接使用，或把 Agent 放到独立 Windows 用户/沙箱。
- **Linux Secret Service：** 取决于会话解锁；同用户同会话进程**可能**可读。
- **Android/OHOS：** 默认按应用沙箱隔离，其他应用不可读。
- **结论：** 保险库解决“明文落盘”，但**不自动解决“同用户 Agent 进程可读”**。真正的边界仍是 DESIGN §2.3 的“Agent 只能拿到引用，实际使用在宿主进程内完成”。

### 2.5 迁移策略

1. **新增 `CredentialVault`，保留旧读路径。** 首次启动时把旧值读出，写入保险库，标记 `vault_migrated_v1`。
2. **双读期。** 读取顺序：保险库 → 旧 SharedPreferences/文件；写路径只写保险库。
3. **删除明文。** 确认所有调用点已改后，删除旧键与 `endpoint.json` 中的 token、`config.toml` 中的 `Authorization`、`credentials.json`。
4. **备份改造。** 全量备份遇到秘密字段时写 `{"credentialRef": "..."}` 而不是值；恢复时要求重新输入或从本机保险库解析。
5. **Agent 工作区改造。** 不再把 token 写进 `config.toml`；改为由宿主启动的本地代理进程持有 token，Agent 只连接本地代理。**这是 Next Shell 的前置条件。**

---

## 3. 设备身份与加密传输

### 3.1 Ed25519 密钥的生成与存储

- **生成：** 每个安装首次启动时生成一对 Ed25519 长期密钥。推荐在 Rust 侧用 `ring` 或 `ed25519-dalek` 生成；本机已有 `ring-0.17.14`（`~/.cargo/registry/src/*/ring-0.17.14`），但 `ed25519-dalek` 不在缓存中，需新增依赖。
- **存储：** 私钥进保险库（§2 推荐方案），公钥与 `device_id` 可存 `device.json` 或 `next.db`。
- **`device_id` 定义：** 沿用 LAN_SECURITY §7.1 的建议 `base64url(SHA-256(Ed25519 public key))`；当前实现只是随机 ID（`lib/next/tasks/device_identity.dart:17-19`），必须替换。
- **不要用 Ed25519 做 ECDH。** LAN_SECURITY §7.1 已明确；密钥交换用 X25519 或 TLS。

### 3.2 设备证书方案

**方案：服务器为 `(账号, 设备公钥, 有效期)` 签名。**

```text
DeviceCertificate {
  version: 1
  account_id: <NipaPlay 账号 ID>
  device_id: base64url(SHA-256(device_public_key))
  device_public_key: Ed25519 public key (raw 32 bytes)
  issued_at, expires_at
  server_signature: Ed25519 signature over the above
}
```

- **离线验证：** 设备 B 收到设备 A 的证书后，用内置的服务器 Ed25519 公钥验证签名，再检查 `account_id` 与自己相同、未过期、`device_id` 与证书内公钥匹配、且该 `device_id` 未被本机吊销列表标记。
- **服务器公钥分发：** 随客户端内置，或由已登录的网关通道获取并缓存。**待验证：** 服务器密钥轮换策略。
- **优点：** 新设备加入不需要所有旧设备在线；吊销列表可本地缓存，服务器不可用时仍能离线验证已缓存证书。
- **风险：** 证书有效期越长，吊销越困难。建议有效期 30 天 + 设备定期续签；吊销通过服务器下发 `revocation_epoch`，设备本地持久化。

### 3.3 设备间双向认证的传输层选型

| 方案 | 实现路径 | 优点 | 限制 |
|---|---|---|---|
| TLS + 自签证书绑定设备公钥 | Dart `SecureSocket` / Rust `rustls` | 成熟、标准、有现成实现；Dart 支持 `SecurityContext.setTrustedCertificatesBytes`、`useCertificateChainBytes`、`usePrivateKeyBytes`、`onBadCertificate`、`peerCertificate.pem`（`~/development/flutter/bin/cache/dart-sdk/lib/io/security_context.dart:117-147`、`secure_socket.dart:54-58`、`:510`） | 需要自己把设备公钥写进证书 SAN/扩展并在握手时校验；Dart 侧没有直接的“pin 公钥”API，需用 `onBadCertificate` + `peerCertificate.pem` 自行校验 |
| Noise（snow） | Rust `snow` crate | 无证书、握手简洁、适合点对点 | 本机 cargo 缓存无 `snow`；Dart 无官方 Noise 实现；需自行处理传输、分帧、重连 |
| 基于现有 Rust FRB 桥 | Rust 实现 TLS/Noise，Dart 只传数据 | 复用 Rust 密码学与设备私钥；跨平台一致 | 需要设计 FRB 流式接口；OHOS/移动端编译验证成本高 |

**推荐：TLS 1.3，双向认证，证书绑定设备公钥。**

- 服务端用设备证书；客户端在 `onBadCertificate` 中提取 `peerCertificate.pem`，解析出公钥并与已登记设备公钥比对；不匹配则拒绝。
- 也可用 `SecurityContext.setTrustedCertificatesBytes` 把已登记设备证书加入信任集，但设备证书是自签的，仍需额外的公钥绑定校验。
- **Dart `SecureSocket` 的限制：**
  - 服务端需要证书链与私钥文件/字节（`SecurityContext.useCertificateChainBytes`、`usePrivateKeyBytes`）。
  - `onBadCertificate` 只给出 `X509Certificate`，其 `pem` 可读，但 Dart 侧解析 X.509 扩展需要额外库。
  - **推测：** 更稳妥的做法是把证书校验放在 Rust 侧，Dart 只做传输。
- **若选 Noise：** 推荐 Rust `snow` + FRB 流式桥；**推测：** 实现成本高于 TLS，但更适合无证书的点对点场景。

### 3.4 在安全通道上承载 Harness 调用

**复用 MCP JSON-RPC 语义，但不复用现有回环 `McpEndpoint`。**

- 现有 MCP 端点只接受 `POST /mcp`、Bearer token、Host/Origin 校验，见 `docs/next/DESIGN.md:325-370`；`McpEndpoint.serve` 只绑定 `127.0.0.1`。
- Mesh transport 应：
  1. 建立 TLS 会话并完成设备双向认证；
  2. 在会话内发送 MCP JSON-RPC 消息（`initialize`、`tools/list`、`tools/call`）；
  3. 服务端校验会话权限后，构造 `Invocation(origin: mesh:<device_id>)` 调用同一 `Harness`；
  4. 返回相同的 `Outcome` envelope。
- **不要把原 MCP listener 改成 `0.0.0.0`。** LAN_SECURITY §8 已明确建议保留回环 MCP 边界，Mesh 是新 transport。
- **能力交换：** `tools/list` 只返回该设备被授权看到的 Action；广播摘要不能替代认证后的能力清单。

### 3.5 防重放与吊销

- **防重放：**
  - TLS 1.3 本身对记录层做序列号保护；
  - 应用层再加 `invocation_id`（UUID）+ `deadline` + `nonce`；服务端维护短窗口的 `invocation_id` 去重表；
  - 会话建立时双方交换 nonce，签名覆盖 `protocol_domain`、双方 `device_id`、双方 nonce、权限。
- **吊销：**
  - 服务器维护 `(account_id, device_id) -> revoked_at`；
  - 设备本地持久化 `revocation_epoch` 与吊销列表；
  - 会话建立时检查对端证书未吊销；
  - 已建立会话在收到更高 `revocation_epoch` 后终止；
  - 服务器不可用时，使用本地缓存的吊销列表，**推测：** 无法保证即时吊销。

---

## 4. 协调服务的最小设计

### 4.1 接口

```text
POST /mesh/v1/devices/register
  Authorization: Bearer <dandanplay_token>
  body: { device_public_key, device_name, platform, app_version }
  → { device_id, certificate, server_public_key, revocation_epoch }

GET /mesh/v1/devices
  Authorization: Bearer <dandanplay_token>
  → { devices: [{ device_id, device_name, platform, last_seen_at, revoked }] }

POST /mesh/v1/addresses
  Authorization: Bearer <dandanplay_token>
  body: { candidates: [{ kind, host, port, priority, expires_at }] }
  → { ok: true }

GET /mesh/v1/addresses?device_id=<id>
  Authorization: Bearer <dandanplay_token>
  → { candidates: [...] }

POST /mesh/v1/devices/<device_id>/revoke
  Authorization: Bearer <dandanplay_token>
  → { revocation_epoch }
```

### 4.2 复用现有令牌验证

现有网关的验证路径：

1. `bearer_token()` 从 `Authorization: Bearer <token>` 提取 token（`server/dandanplay-gateway/src/main.rs:566-572`）。
2. 非登录/注册接口要求 token 或 webToken（`:274-285`）。
3. `validate_account_token()` 用 `GET /api/v2/playhistory?withRelatedBangumi=false&pageIndex=0&pageSize=1` 请求上游，带 `X-AppId`、`X-Timestamp`、`X-Signature`（`:428-451`）。
4. 上游返回 401/403 → 无效；非 2xx → 验证失败；2xx 且 `success == true` → 有效（`:453-464`）。
5. 验证结果缓存：有效 600 秒、无效 30 秒（`:110-130`）。

**复用方式：** 把 `validate_account_token` 抽成共享 crate 或模块，协调服务直接调用；不要复制粘贴，避免缓存与签名逻辑分叉。

### 4.3 存储、限流、心跳与负载

- **存储：** SQLite 单文件足够。
  - `devices(account_id, device_id, public_key, name, platform, created_at, last_seen_at, revoked_at)`
  - `addresses(device_id, kind, host, port, priority, expires_at, updated_at)`
  - `certificates(device_id, issued_at, expires_at)`
- **限流：**
  - 按账号：`register` 10/小时、`addresses` 60/小时、`devices` 120/小时；
  - 按 IP：全局 300/分钟；
  - 复用网关已有的 `RateLimiter` 思路（`server/dandanplay-gateway/src/main.rs:70-180`）。
- **心跳频率：** 建议 15 分钟一次地址上报，服务器不可用时指数退避到 1 小时。
- **负载估算：**
  - 假设 10 万设备，每 15 分钟一次心跳 → 约 111 QPS 峰值若均匀分布；但实际会集中，需限流。
  - 每次请求只读写 SQLite 单行，**推测：** 单核可支撑，但需要 WAL 模式与连接池。
  - 服务器性能很弱，建议把心跳间隔放宽到 30 分钟，并在客户端做随机抖动。

### 4.4 独立二进制 vs 网关模块

| 方案 | 优点 | 缺点 |
|---|---|---|
| 独立二进制 | 职责清晰；可独立限流、部署、回滚；不拖累网关 | 多一个进程与数据库 |
| 网关模块 | 复用验证代码与部署 | 网关是透明反代，加入账户/设备表会扩大攻击面；服务器性能弱时相互影响 |

**推荐：独立二进制 `nipaplay-mesh-coordinator`，共享一个 `nipaplay-auth` crate 做令牌验证。**

---

## 5. 连接建立

### 5.1 地址候选来源

1. **本机网卡：** 枚举非回环、非链路本地地址。
2. **局域网广播：** 现有 UDP 32123 发现（`lib/services/nipaplay_lan_discovery.dart:6`、`:35-43`），仅作线索，不授予信任。
3. **用户手填 overlay/公网地址：** Tailscale、ZeroTier、WireGuard、VPS 地址。
4. **服务器地址候选：** 由协调服务下发，低频更新。

### 5.2 直连尝试顺序

1. 已缓存且最近成功的地址；
2. 同局域网候选（UDP 发现 + mDNS/广播）；
3. 校园网/内网可路由地址；
4. 用户 overlay 地址；
5. 用户自有中继节点。

每个候选都先做 TLS 握手 + 设备证书校验；失败的候选记录退避。

### 5.3 校园网典型限制与可行路径

- **广播被禁：** UDP 发现不可用；改用服务器地址候选或用户手填。
- **客户端隔离：** 同网段设备无法直连；需要 overlay 或中继。
- **跨网段：** 需要可路由地址或 overlay。
- **可行路径：** 用户自有 overlay（Tailscale/ZeroTier/WireGuard）是最稳的；其次是用户 VPS 中继。

### 5.4 用户自有节点中继的最小方案

- **不经过 NipaPlay 服务器。**
- 用户 VPS 运行一个最小 TCP/TLS 中继：只按 `device_id` 转发字节流，不解析 MCP、不存媒体。
- 中继本身不持有设备私钥，只做流量转发；端到端 TLS 仍由两端设备完成。
- **最小实现：** Rust `tokio` TCP 转发 + 连接认证；**推测：** 可复用现有 `rustls` 依赖。

---

## 6. 与 LAN_SECURITY 第 6、7 节的关系

### 6.1 A 档修复与 Mesh 的顺序

**先做 A1/A3/A5/A6，再做 B/Mesh：**

- **A1（token 外层 URL 泄露）：** 必须先修，否则 Mesh 上线后旧接口仍可能泄露账号 token。
- **A3（撤销立即生效）：** 必须先修，否则设备吊销语义不一致。
- **A5（敏感日志与缓存）：** 必须先修，否则 Mesh 的 invocation 日志可能泄露 token/路径。
- **A6（CORS 一致性）：** 建议先修，减少浏览器侧攻击面。
- **A2/A4/A7：** 可与 Mesh 并行，但不应阻塞最小版。

### 6.2 Mesh 上线后应只在安全通道提供的旧接口

| 旧接口 | 处理 |
|---|---|
| `/api/dandanplay/*`（登录、WebToken、历史、收藏、发弹幕） | 只在安全通道提供；`/api/dandanplay/webtoken` 必须移除匿名访问 |
| `/api/media/local/manage/*`（folders、WebDAV、SMB、browse、stream） | 只在安全通道提供；凭据不返回客户端 |
| `/api/history/progress` | 只在安全通道提供；与 share stream 的资源授权分离 |
| `/api/web_proxy`、`/api/image_proxy` | 只在安全通道提供；并加 SSRF 边界 |
| `/api/remote/control/command` | 迁移到 Mesh transport |
| `/api/media/local/share/episodes/*` | 改为资源票据；票据只授权单个资源 |
| `/api/info`、UDP 32123 发现 | 保留为无秘密线索接口 |
| `/api/bangumi/*`、`/api/search/*` | 可保留只读匿名，但不应返回账号数据 |

### 6.3 迁移顺序

1. A 档修复；
2. 保险库迁移；
3. 设备身份与证书；
4. 安全 transport 双栈；
5. 新客户端优先安全通道；
6. 旧接口标记 deprecated；
7. 关闭匿名敏感 API。

---

## 7. 最小版 Mesh 建议范围

### 7.1 场景

**Mac 上的 Agent 调用工位机 NipaPlay 的 Harness，包括 `task.*` 与 `download.*`。**

### 7.2 建议 Action

| Action | Effect | 说明 |
|---|---|---|
| `mesh.devices` | read | 列出已认证设备与在线状态 |
| `mesh.invoke` | 取决于被调用 Action | 统一入口，输入 `{ deviceId, action, input }`；权限由被调用 Action 决定 |
| `task.list` / `task.get` / `task.wait` / `task.cancel` | read/write | 复用现有实现（`packages/nipa_harness/lib/src/tasks/actions.dart:33-34`） |
| `download.add` / `pause` / `resume` / `remove` | write | 复用 `lib/next/capabilities/download_capability.dart:50-51` |
| `download.delete` | destructive | 必须保留 `Effect.destructive`，默认本机确认 |

**备选：按设备路由。** 例如 `task.list@device`、`download.add@device`；**推测：** 这会污染 Action ID 空间，不如 `mesh.invoke` 干净。

### 7.3 风险清单

| 风险 | 说明 | 缓解 |
|---|---|---|
| 设备私钥泄露 | 保险库被攻破 | 平台安全存储 + 短证书 + 吊销 |
| 服务器被攻破 | 可伪造设备证书 | 服务器只签证书，不持设备私钥；证书短期 |
| 中继被攻破 | 用户 VPS 可看流量 | 端到端 TLS，中继只转发 |
| Agent 误用 | `download.delete` 等破坏性操作 | `Effect.destructive` + 本机确认 |
| 重放 | 攻击者重放 MCP 调用 | invocation_id + nonce + deadline |
| 权限扩散 | A 设备信任 B，B 可调用所有 Action | 按 Action 授权；不隐式传递 |
| 地址泄露 | 服务器存储用户公网地址 | 加密存储或只存哈希；低频清理 |
| 旧接口旁路 | 旧 `/api` 仍可匿名调用 | 按 §6 顺序收口 |
| 备份泄露 | 备份文件含 token | 保险库迁移后备份只存引用 |
| 日志泄露 | journal.jsonl 含输入 | 过滤 secret 字段 |

---

## 8. 待验证事项

1. HarmonyOS HUKS 在 Rust/NAPI 侧的可用 API 与最小示例。
2. tvOS Keychain 在 flutter-tvos 下的实际运行行为（本机只有源码，未运行）。
3. Windows Credential Manager 是否满足“Agent 进程不可读”；**推测：** 默认不满足。
4. Linux 无 Secret Service 时的降级策略与用户提示。
5. 服务器 Ed25519 签名密钥的轮换与历史证书验证。
6. 用户自有中继的最小认证协议。
7. Dart `SecureSocket` 在 tvOS/OHOS 上的可用性；**推测：** tvOS 可能可用，OHOS 需要验证。
8. `journal.jsonl` 当前是否已记录敏感输入；需实际检查运行日志格式。

---

## 9. 参考

- 工作区：`docs/next/DESIGN.md`、`docs/next/research/LAN_SECURITY.md`
- 网关：`server/dandanplay-gateway/src/main.rs`、`server/dandanplay-gateway/README.md`
- Next：`lib/next/agent_endpoint.dart`、`lib/next/agent_workspace.dart`、`lib/next/media/provider_transport.dart`、`lib/next/tasks/device_identity.dart`
- 依赖缓存：`~/.pub-cache/git/plugins-79dc1ac13b94d593e2361bf10b5ed8bdd225d3db/packages/flutter_secure_storage_tvos/`、`~/.cargo/registry/src/*/`
- Dart SDK：`~/development/flutter/bin/cache/dart-sdk/lib/io/secure_socket.dart`、`security_context.dart`