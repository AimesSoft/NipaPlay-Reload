# X10：凭据按需读取与授权拒绝状态

日期：2026-10-11。仓库：`~/Desktop/NipaPlay-Reload`，分支：`next/capability-layer`。已先读 `TEAM.md`。

## 1. 完成了什么

- 启动不再探测一个无关的 availability 条目，也不再全量迁移、读回校验所有偏好、Next 凭据文件和旧同步缓存的秘密。弹弹play 登录 token 的启动读取及必要迁移保留。
- Emby/Jellyfin、弹弹play 远程媒体库的启动初始化只加载元数据。打开对应媒体库、进入服务器详情或创建播放会话时，恢复所需服务器连接，只解析选中配置的 token。SMB/WebDAV 列出连接不读取密码，实际验证、列目录、播放和下载字幕时解析选中连接。
- 连接与服务器模型保留未解析引用。元数据保存、备份和复制模型无需解开秘密；未改密码的编辑保留原引用。表单捕获打开时的输入值，避免后台解析密码后将未修改的空字段误判成新密码。未解析密码有“留空保留”的提示。
- `SessionCredentialVault` 统一覆盖 Classic 的适配器和 Next 直接使用 vault 的路径。授权拒绝、取消以及系统禁止授权交互按 `CredentialRef` 阻止本次运行的自动读取、写入和删除；同一条目的并发读取合并。其他条目仍可正常访问。
- 全局界面显示具体引用、拒绝事实和逐条重试按钮。`credentials.status` 返回结构化 `failures`，包含 `reference`、`reason`、`automaticRetryBlocked`；查询状态不访问保险库。新增 `credentials.retry`，与 GUI 使用同一主动重试入口，只返回引用和存在状态，不返回秘密。
- 提示按 macOS、Linux、Windows 分别提供说明；macOS 不再显示 Linux Secret Service。拒绝启动必需的弹弹play token 时，应用可以继续启动并显示事实；仅本次内存登录状态不可用，持久 token、登录标志和钥匙串条目不删除。

没有 commit、push、pub get、依赖修改，也没有退出或重启真实 NipaPlay。开始时已存在的 `macos/Podfile.lock` 修改保留原样；本任务未改它。测试均使用内存保险库；没有读写用户真实钥匙串条目。

## 2. 决策

**按需解析放在功能入口和模型中。** 仅删除 main 的保险库探测无法解决问题：服务启动仍会整批解开服务器与连接密码，Next 元数据运行时还会迁移全部文件。现在服务先加载引用，选定功能再解析，避免一个拒绝条目阻塞其他连接。

**拒绝抑制放在共享 vault 包装层。** `credentials.status`、后台轮询和页面刷新不能解除抑制；GUI 的逐条按钮或用户要求下的 `credentials.retry` 才解除指定条目并读取一次。用户随后再次连接时使用正常服务入口。重试再次被拒绝会重新阻止该条目，不阻止其他条目。状态仅属于本次运行，不把“曾经拒绝”变成跨运行永久封锁。

**保留 macOS 原始错误码。** keyring 3.6.3 将 `errSecUserCanceled` 和 `errSecAuthFailed` 都归入 `PlatformFailure`，现有 Rust 映射再把它们归为 `system_vault_unavailable`，无法据此报告拒绝事实。macOS 路径改为直接调用同一组 Security.framework generic-password API，继续使用 User domain 默认钥匙串、服务名 `com.nipaplay.credential-vault.v1` 和原有长度前缀 account 编码；保留原条目，更新仍用 ModifyAttributesAndData，不修改访问控制，也不删除重建。`-128`、`-25293`、`-25308` 分别映射取消、拒绝、禁止交互。Windows/Linux 保留 keyring 后端。未新增依赖，FRB 接口签名未变。

**迁移仍以写后读回成功为提交条件。** 新写入失败不落明文；拒绝读回时保留旧源值与已存在的保险库值，不清理凭据。标量旧值在实际读取时尝试迁移，Next 元数据文件仅迁移当前请求的引用，组合连接旧值在显式保存时走原有验证写入。旧同步缓存不再为启动进行全量保险库写入和读回，原文件保留，完整诊断迁移接口仍存在。没有把已保存的保险库秘密复制回偏好或文件。

**显式开启的功能仍可使用必需秘密。** 例如已启用的自动同步和已配置启动的 Mesh，真正执行连接时仍使用它们所需的凭据；这次修改不取消用户已开启的功能。备份收集弹弹play 远程配置时只加载元数据，不再借备份触发远程 token 读取和联网刷新。

## 3. 实验与验证

### 内存保险库实验

实验位于 `test/security/credential_access_experiment_test.dart`。使用真实服务的元数据加载入口、实际弹弹play初始化、实际 `CredentialNotice` 和 Harness Action；保险库是 `MemoryVault`，WebDAV 网络验证为可计数替身。准备两条 SMB、两份服务器配置和一条 WebDAV 凭据，执行启动、拒绝、六次自动调用、GUI 重试、Agent 重试、取消与主动重新验证。

命令（未访问网络或真实钥匙串）：

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub --reporter expanded \
  test/security test/network_media_server_dialog_test.dart
```

真实输出摘录：

```text
X10 startup: essentialReads=1, nonessentialReads=0, smbMetadata=2, webdavMetadata=1, profiles=2
[CredentialVault] CredentialRef(smb_connections, smb-one): storage_access_denied
X10 refused: backendReads=1, automaticAttempts=6, GUI=访问被拒绝, macOSLinuxText=false
X10 agent: {"status":"completed","result":{"backend":"system","notices":["凭据访问或迁移失败。请在 macOS 钥匙串访问中检查此条目的访问权限。 现有凭据已保留；未回落到明文存储。","CredentialRef(smb_connections, smb-one): 访问被拒绝；本次运行已停止自动重试，可主动重试。"],"failures":[{"reference":{"namespace":"smb_connections","key":"smb-one"},"reason":"storage_access_denied","automaticRetryBlocked":true}]}}
X10 user retry: backendReads=3, resolved=true, blocked=0, notices=0
X10 agent retry: {"status":"completed","result":{"reference":{"namespace":"smb_connections","key":"smb-one"},"available":true}}
X10 preservation: bothSecretsRetained=true, unusedEntryReads=0, plaintextPreferences=false
[CredentialVault] CredentialRef(webdav_connections, webdav-one): storage_authorization_cancelled
X10 cancelled: reference=CredentialRef(webdav_connections, webdav-one), backendReads=1, networkValidations=0, automaticRetryBlocked=true
X10 explicit reconnect: success=true, networkValidations=1, otherSMBReads=0, otherServerReads=0
00:01 +22: All tests passed!
```

`backendReads=3` 是总计：一次拒绝，点击 GUI 重试的一次成功读取，随后连接模型解析的一次成功读取；拒绝与主动操作之间没有第二次后端读取。成功值只在使用它的模型中缓存，vault 不永久缓存成功读取结果。

还验证了未打开服务器 token 的保存仍为原引用、未修改密码的编辑在后台解析后仍为引用，且两条 SMB 的秘密都保留。数据保护测试覆盖拒绝读回后不改旧偏好、不自动重写、主动恢复后可完成迁移；并发取消只有一次后端读取；新运行可再次访问；拒绝必需登录不删除持久登录；失败的新写入不创建明文偏好。原有迁移、备份、恢复和日志脱敏测试一起运行。

### Classic 回归

回归覆盖 security 全目录、远程路径、媒体服务基类、SMB 代理启动、Jellyfin 授权、Emby/Jellyfin 隔离、分页、服务器对话框、弹弹play 授权及登录提示、HTTP 客户端、媒体源目录、播放同步与字幕 User-Agent。回环 HTTP 用命令级清空代理变量，Jellyfin fixture 的 `HttpClient.findProxy` 也明确返回 `DIRECT`。

```sh
HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= http_proxy= https_proxy= all_proxy= \
~/development/flutter-3.44.6/bin/flutter test --no-pub --reporter expanded \
  test/security test/media_source_utils_test.dart \
  test/media_server_service_base_test.dart test/smb_proxy_startup_test.dart \
  test/jellyfin_authorization_test.dart test/emby_jellyfin_isolation_test.dart \
  test/media_server_pagination_integration_test.dart test/network_media_server_dialog_test.dart \
  test/utils/dandanplay_auth_test.dart test/dandanplay_login_notice_test.dart \
  test/dandanplay_http_client_test.dart test/emby_media_source_catalog_test.dart \
  test/media_server_playback_sync_user_agent_test.dart
```

```text
00:03 +81: All tests passed!
```

随后增加编辑表单打开值的保护并再次执行上面的 22 项 security/对话框检查，全部通过。

### Rust 与静态检查

```sh
cargo test --offline --locked --manifest-path rust/Cargo.toml vault::tests -- --nocapture
```

```text
test vault::tests::authorization_status_codes_are_distinct ... ok
test vault::tests::missing_and_deleted_entries_are_idempotent ... ok
test vault::tests::reference_boundaries ... ok
test result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 123 filtered out; finished in 0.00s
```

这些测试仅检查错误码和 keyring mock，没有调用系统保险库操作；macOS Security.framework 路径已编译、链接。没有按此推断真实签名构建的钥匙串授权弹窗已验收。

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub lib/security
~/development/flutter-3.44.6/bin/flutter analyze --no-pub lib test/security test/jellyfin_authorization_test.dart
git diff --check
```

保险库代码检查：`No issues found!`。后一个检查无 error，输出 `1967 issues found. (ran in 4.1s)`，包含应用已有 lint 和实验真实输出所用 print 的提示，退出状态不是零；未为本任务清理无关 lint。`git diff --check` 无输出、退出 0。

### 意外与失败

- 首轮有两个旧备份测试把 `store.vault` 强制转换为 `MemoryVault`，共享包装加入后转换失败；已改为检查包装的内存 backend，重跑通过。
- 实验初稿误用 Outcome 的 `toJson`，编译失败；改用 Harness 的 `toEnvelope`。初期模型补丁还出现一个重复三元运算符，静态检查发现并修复；最终检查无编译错误。
- 扩大回归时，旧 Jellyfin 授权测试没有替换持久层，报 `Failed to load dynamic library 'rust_lib_nipaplay.framework/rust_lib_nipaplay'`，连接测试失败。这发生在库加载阶段，尚未进行系统钥匙串读写。已在该测试中注入内存保险库并设置回环直连，随后 81 项通过。
- 最初运行不指定范围的仓库 analyze，得到 5442 条问题，包含示例与 third_party 测试项目未安装依赖的 URI/class 错误。没有运行 pub get 或修改这些项目；最终检查主应用与相关测试，无编译错误。

## 4. 需要主控决定的问题

没有。真实钥匙串弹窗、历史二进制访问控制与签名链的验证留给主控的真机验收；本任务按约束只做内存替身实验和不访问钥匙串的编译验证。

## 主控补充（2026-10-11）

- `test/next/media_provider_test.dart` 仍调用已删除的 `VaultCredentialResolver.initialize()`，导致编译失败；改为直接验证 `resolve` 不生成明文文件。`test/next` 与 `test/security` 共 377 项通过。
- 待真机核对：Classic 启动时对已配置 Jellyfin / Emby 的自动连接是否保持。将在实验配置中用临时 Jellyfin / Emby 验证。
