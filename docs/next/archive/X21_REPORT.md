# X21：插件偏好分类与凭据引用恢复回归修复

日期：2026-10-11。工作目录：`~/Desktop/nipaplay-next-wt/plugin-backup`，分支：`next/plugin-backup`。已先读 `TEAM.md` 与 `X18_REPORT.md` 第 4 节；Classic 行为的调整依据本任务主控的明确决定。没有 commit、push、改依赖或运行 pub get。

## 1. 完成了什么

- `CredentialStore.isSecretKey` 不再按 `plugin_` 前缀一律判秘密。启用列表、下载覆盖和插件开关明确排除；插件文本和其他偏好统一按 password、passwd、cookie、token、secret、API key、authorization 及对应中文名称判断。现有明确秘密键和保险库内部键继续视为秘密。
- 新备份按值导出插件结构偏好与公开文本；登录 token、插件 API key 等仍只导出凭据引用。没有改变 `.npb` 的版本号。
- 已经被旧分类迁入保险库的公开文本，读取和导出时解析原引用，导出公开值；原偏好引用与保险库条目保持原存储方式，正常写入也继续使用该已有引用。没有批量解密迁移、删除条目或重写既有存储。
- 恢复时，无法解析或被保险库拒绝读取的引用会跳过受影响的恢复项，保留当前持久值，记录项路径、引用及原因。覆盖偏好、媒体库连接、账户、观看历史和剧集匹配，包括错误分类产生的旧备份。
- 总结果和分类结果提供 `status` 与逐项 `skippedItems`，总跳过数包含所有分类。存在未解析引用时 `success=false`，根据其余数据是否恢复返回 `partial` 或 `skipped`，不报告为完整恢复成功。Classic 页面显示“部分恢复”或“恢复已跳过”、保留现值及具体原因；Agent 的 `backup.restore` 返回相同信息。
- 更新 X18 原实验中记录旧缺陷的断言，补充持久数据约束回归和 X21 临时目录实验。

涉及实现：`lib/security/credential_store.dart`、`lib/security/portable_credentials.dart`、`lib/services/full_backup_service.dart`、`lib/next/settings/operations.dart`、Classic `backup_restore_page.dart`。实验入口：`test/security/plugin_backup_experiment_test.dart`。

## 2. 决策

1. **分类与历史存储形式分开处理。** 一个公开字段可能已经存成保险库引用。只放宽分类会让它读到引用 JSON；现在仍按匹配该偏好键的既有引用读取，导出时异步取公开值。登录秘密的导出不解析引用。已有公开引用缺失时导出失败，保留本地存储，不伪造公开值。统一名称判定时也明确排除已知的 token 续期时间及是否需要 token 的开关，避免误分类非秘密元数据；实验检查续期时间仍按整数导出和恢复。
2. **按实际恢复单元跳过。** 普通偏好和结构列表整项处理；连接、服务器账户、观看历史和剧集匹配按记录处理。一个单元内任意引用无法解析，整个单元不进入原恢复路径，避免部分字段变空或账户元数据与当前登录秘密错配。其余单元继续沿用原合并规则。结构列表不删除单个失败元素后再覆盖原列表。
3. **保留原恢复/同步水合函数的默认契约。** 为完整备份恢复增加未解析回调；恢复器根据回调移除待应用单元。直接使用水合函数的其他调用仍保持原契约。保险库异常通过已有安全原因码报告，不将外部异常文本作为原因返回。
4. **恢复不完整时明确失败布尔值和实际状态。** `success=false` 表示没有完整恢复所选数据；`status=partial/skipped` 和原因说明已恢复、已跳过的区别。历史中原本的重复记录跳过规则继续保留，不将重复数据当作凭据失败。媒体库中没有通用 restoredCount 的成功设置也计入状态判断。
5. **实验使用真实文件偏好与 SQLite，不启动窗口。** 直接使用现有 `LabPreferences` 将偏好落到临时 JSON，存储和路径 override 指向同一临时根，保险库替换为 MemoryVault。通过真实 PluginService、内置插件 JS runtime、全量备份文件导出/导入和重新载入插件服务观察功能；不需要真实钥匙串或用户数据。

## 3. 实验

### 隔离和命令

全部命令使用本 worktree 和 Flutter 3.44.6。X21 的 `nipa-x21-*` 临时目录中包含偏好 JSON、插件目录、SQLite 和 `.npb` 文件；finally 关闭数据库、释放插件运行时、还原 override 并删除目录。X18 回归仍使用其原临时目录与清理流程；回环 HTTP 实验沿用 DIRECT，同时移除代理环境变量。

没有在主仓库构建，没有构建或启动应用窗口，没有启动 `/Applications/NipaPlay.app`，没有访问用户钥匙串或真实数据目录。

最终回归命令，原始输出保存在 `/tmp/nipa-x21-regression.log`：

```sh
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/security test/next/settings_registry_test.dart \
  test/next/settings_rest_experiment_test.dart \
  test/plugins/plugin_runtime_resolution_test.dart --reporter expanded
```

### 插件启用 → 全量备份 → 停用 → 恢复

启用内置正则插件并确认 loaded；导出五分类 `.npb`；停用后确认持久启用列表为空；导入五分类，再创建新的 PluginService 重读持久状态。备份中列表/下载覆盖/开关保留原类型，公开文本保留原值。fixture 还包含一个被旧分类迁入保险库的公开文本和两个登录秘密。

以下为最终输出原样摘录：

```text
X21 export: enabled=["builtin.cn_danmaku_regex_filter"]; override=true; switch=true; public=公开文本; vaultedPublic=保险库中的公开文本; storedPublicUnchanged=true; vaultUnchanged=true
X21 login export: {"credentialRef":{"namespace":"preferences","key":"dandanplay_token"}}; plugin secret export: {"credentialRef":{"namespace":"preferences","key":"plugin_text_setting_demo::api_key"}}; secretBytesAbsent=true
X21 before restore: enabled=[]
恢复了 7 项偏好设置
恢复了 0 个本地媒体库路径
恢复了 0 个服务器配置
恢复了Nipaplay媒体库共享配置
观看历史恢复完成: 恢复 0 条，跳过 0 条
剧集匹配恢复完成: 恢复 0 条，跳过 0 条
恢复了弹弹play账户信息
备份恢复完成
X21 full roundtrip: status=completed; enabled=["builtin.cn_danmaku_regex_filter"]; reloadedEnabled=true; reloadedLoaded=true; skipped=0; vaultUnchanged=true; storedPublicUnchanged=true
```

备份文件全文检查不含两个秘密的实际字节。重新载入后不仅偏好列表正确，插件的 enabled 和 loaded 也都为 true。保险库内容在导出及恢复前后深比较相同，既有公开文本的原引用字符串保持相同。

### 错误分类产生的旧备份

按修复前实际格式构造 version=2 的 `.npb`：启用列表、下载覆盖和公开文本三个键的值均是对应 preferences credentialRef，保险库中没有对应值。恢复前保留当前已启用插件、覆盖=true 和公开文本。恢复后比较当前值、偏好 JSON 全部字节及保险库内容。

```text
已跳过 plugin_enabled_ids：凭据引用无法解析，保留现值 (credential_missing)
已跳过 plugin_downloader_override：凭据引用无法解析，保留现值 (credential_missing)
已跳过 plugin_text_setting_demo::label：凭据引用无法解析，保留现值 (credential_missing)
恢复了 0 项偏好设置
备份恢复已跳过：已跳过 3 项无法解析的凭据引用，保留现值
X21 old-format restore: {"success":false,"status":"skipped","restoredCount":0,"skippedCount":3,"skippedItems":[{"path":"plugin_enabled_ids","reason":"credential_unresolved","references":[{"credentialRef":{"namespace":"preferences","key":"plugin_enabled_ids"},"reason":"credential_missing"}]},{"path":"plugin_downloader_override","reason":"credential_unresolved","references":[{"credentialRef":{"namespace":"preferences","key":"plugin_downloader_override"},"reason":"credential_missing"}]},{"path":"plugin_text_setting_demo::label","reason":"credential_unresolved","references":[{"credentialRef":{"namespace":"preferences","key":"plugin_text_setting_demo::label"},"reason":"credential_missing"}]}],"error":null,"localLibraryCount":0,"serverProfileCount":0,"serverAccountCount":0,"dandanplayRestored":false,"bangumiRestored":false}; current={"plugin_enabled_ids":["builtin.cn_danmaku_regex_filter"],"plugin_downloader_override":true,"plugin_text_setting_demo::label":"公开文本"}; preferenceFileUnchanged=true; vaultUnchanged=true
```

### 其他持久数据约束

额外 `.npb` 实验在已有 SQLite 历史及匹配记录旁，恢复缺失 URL 凭据引用的历史/匹配各一条。经备份文件解析和批次合并，原 SQLite 行、偏好文件和保险库内容均未改变，两个失败记录没有计入 restoredCount：

```text
X21 missing history references: status=skipped; restored=0; skipped=2; sqliteRowsUnchanged=true; preferenceFileUnchanged=true; vaultUnchanged=true
X21 cleanup: temporaryDirectoryExists=false
```

数据约束测试另覆盖：12 个未解析单元涉及普通偏好、结构列表、当前登录账户、服务器、WebDAV、SMB 和远程服务时，全部当前偏好及保险库内容保持相同；保险库拒绝访问返回 storage_access_denied，保留秘密且继续恢复普通语言设置；媒体库公开选项可恢复，同时保留带失效引用的服务器配置，结果为 partial。原明文旧备份登录秘密仍能按原流程写入保险库。

### X18 原场景与最终检查

X18 原 Agent 实验仍验证设置来源、Classic widget、五分类内容比较和观看位置；其插件回归探针现在观察到：

```text
X18 repaired Classic backup: plugin_enabled_ids exported=["builtin.cn_danmaku_regex_filter"]; after=["builtin.cn_danmaku_regex_filter"]
00:02 +43: All tests passed!
```

本次修改的 10 个 Dart 文件运行 targeted analyze，命令包含 `--no-pub`，结果保存在 `/tmp/nipa-x21-analyze.log`；`git diff --check` 通过：

```text
Analyzing 10 items...
No issues found! (ran in 5.1s)
```

### 失败与实验边界

- 首轮回归有一个新增断言错误：我把新主机账户 fixture 的跳过数写成 1；真实输出为 `Expected: <1> / Actual: <3>`，因为还包含 Bangumi 和服务器账户。改为检查实际 3 项；该轮日志 `/tmp/nipa-x21-first.log`。
- 扩展回归发现旧注册表测试仍把 `plugin_text_setting_fixture::key` 和公开 custom_value 当作必禁秘密。真实输出 `Expected: true / Actual: <false>`，已将秘密 fixture 改成 api_key/token，并检查公开键不再被旧前缀规则禁止；失败日志 `/tmp/nipa-x21-regression-first.log`。
- Flutter test 没有 Rust framework，输出 `Rust 增量同步编解码不可用，回退 Dart 实现`，文件编解码走原 Dart fallback。X18/注册表测试也有原有 mock 环境的 Wakelock、原生方法不可用日志；最终测试全部通过。
- 没有验证 Rust 原生编解码、原生钥匙串、应用构建或桌面窗口。X21 五分类 fixture 的历史/连接列表为空；非空历史、媒体库与服务器账户的正常往返沿用 X18 实验，未解析历史另以真实 SQLite 验证。不能据此声称完成所有原生环境或网络连接恢复的验证。

## 4. 问题：需要主控决定

没有。
