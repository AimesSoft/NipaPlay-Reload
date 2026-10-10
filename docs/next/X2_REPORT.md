# X2：macOS 去沙箱与数据迁移

工作目录：`~/Desktop/nipaplay-next-wt/desandbox`；分支：`next/desandbox`。依据 `/tmp/nipa-next/DESIGN-v2.md` §5。未 commit、未 push、未修改依赖；未启动 NipaPlay.app，未读取或迁移真实用户容器。

交付摘要：

1. 完成：Debug/Release 去掉 App Sandbox；实现启动前可恢复迁移、书签兼容、沙箱进程禁用 Next，并调整 GitHub 签名检查。
2. 决策：保留原容器和完整校验归档；已有普通位置的数据组优先，偏好逐键补缺，不混合 SQLite 与旧 WAL。
3. 验收：20 项迁移测试、21 项 Flutter 测试通过；analyze 无新增问题；macOS Debug 构建成功，codesign 确认无 app-sandbox；独立原生冒烟验证通过。
4. 主控需决定的问题：没有。真实用户迁移及正式签名升级、公证验证由主控在备份后执行。

## 1. 完成了什么

`DebugProfile.entitlements`（同时用于 Debug/Profile）及 `Release.entitlements` 删除 App Sandbox 和仅用于沙箱的文件／网络权限。保留 Flutter 的 `allow-jit` 和相机权限；Debug/Profile 允许调试和加载本机原生库。macOS 配置明确 `ENABLE_APP_SANDBOX = NO`、`ENABLE_HARDENED_RUNTIME = YES`。bundle ID 仍为 `com.aimessoft.nipaplay`。

`MainFlutterWindow.awakeFromNib()` 在创建、运行 FlutterEngine 前执行原生迁移。数据迁移失败会显示原生错误并退出，下一次启动恢复；不会继续打开半迁移的数据。沙箱进程不执行迁移。现有 `NIPAPLAY_DATA_DIR` 隔离 Debug 启动也不迁移生产数据；Release 不使用这项 Debug 隔离规则。

新增 `SandboxMigration.swift` 和独立原生测试。Dart 中旧的 Documents 根目录迁移仅在沙箱进程继续使用；非沙箱升级由新迁移负责，避免旧迁移在新位置再次覆盖数据、删除旧副本。

通过原生 `sandbox_check(getpid(), nil, 0)` 查询实际进程状态，并经已有 `security_bookmark` channel 交给 Dart。`LabsSettingsProvider.nextAvailable` 控制 Next 的可用性；保存为开启的旧偏好在沙箱进程中也呈现关闭，拒绝重新开启，原偏好仍保留。NextRuntime 原有启动判断读取这个受限 getter，因此不会启动 Agent endpoint。Classic 下载使用的共享 NextCore 基础设施继续保留。

实验室页面仅增加 8 行：禁用开关、展示中／繁／英文原因及 GitHub 完整版提示，并禁用当时依赖 Next 的平台登录入口（该入口现已在 X6 删除），便于与另一位组员的知情同意改动合并。没有新增构建变体，没有改动 Windows/Linux/iOS/Android 的平台逻辑。

书签原生层按实际沙箱状态选择 security-scoped 或普通 bookmark。非沙箱解析不再把 `startAccessingSecurityScopedResource() == false` 当作失败。Dart 层也接受正常解析出的非 scoped 路径，只记录真正启动过的 security scope，支持过期书签刷新。原有书签字节随偏好保留。

GitHub 的 `.github/actions/build-macos/action.yml` 保留原有逐库签名、hardened runtime、timestamp、notarytool 与 stapler；签名身份限定 Developer ID Application，删除 Development／其他证书回退。签名后新增构建产物检查，拒绝含 app-sandbox 或缺少 allow-jit 的 GitHub 产物。

## 2. 决策及依据

### 实际存储位置

先追踪应用及已经解析的原生插件代码，没有检查真实用户容器。下表中源路径都相对 `~/Library/Containers/com.aimessoft.nipaplay/Data/`。

| 实际使用位置 | 代码依据 | 非沙箱位置／处理 |
|---|---|---|
| `Documents/nipaplay/` | `lib/utils/storage_service.dart` 的默认存储；`watch_history_database.dart` 的 DB、JSON；图片／弹幕／下载缓存等使用 StorageService | `~/Documents/nipaplay/`，作为完整数据组发布 |
| 历史版本的 `Documents/` 根目录数据 | `lib/utils/macos_storage_migration.dart` 的旧版迁移；已有旧观看历史和缓存命名 | 整理到新 `Documents/nipaplay/`；容器内已经规范化的同名数据优先；两份原始内容都完整归档 |
| `Documents/nipaplay/next/` | `lib/next/next_core.dart`、`next_database.dart`：Next DB、身份、任务、Mesh、工作区等 | 随整个应用文档组发布，不拆分 Next 数据库及其关系 |
| `Library/Application Support/com.aimessoft.nipaplay/` | `path_provider_foundation 2.5.1` 在 macOS 的 applicationSupport 追加 bundle ID；字幕字体、shader、增量同步索引、托盘资源、single_instance 等调用此 API | 对应 `~/Library/Application Support/com.aimessoft.nipaplay/` |
| `Library/Application Support/NipaPlay/torrent_session/` | `rust/src/api/torrent.rs::default_session_dir` 使用 HOME；这一路径与 Flutter 的 bundle ID 子目录不同 | 对应 `~/Library/Application Support/NipaPlay/torrent_session/`，已加入迁移测试 |
| `Library/Caches/` 及 bundle ID 子目录 | `path_provider_foundation 2.5.1`：applicationCache 追加 bundle ID，**getTemporaryDirectory 在 macOS 实际使用 Caches，不追加 bundle ID**；AppDelegate 的 Vulkan ICD 也使用 Caches | 按实际子项迁移到 `~/Library/Caches/`；不只复制 bundle ID 子目录 |
| rqbit 的 `Library/Caches/com.rqbit.dht/` | 当前 Cargo.lock 的 librqbit-dht 9.0.1，通过 directories 的 ProjectDirs 保存 DHT 缓存 | 同样随 Library/Caches 的实际子项迁移 |
| `Library/Preferences/com.aimessoft.nipaplay.plist` | `shared_preferences_foundation 2.5.6` 的 `UserDefaults.standard`／persistentDomain | 经 UserDefaults/cfprefsd 写入普通偏好域并 synchronize、读回校验；不直接替换正在由系统管理的 plist |
| `security_bookmark_*`、扫描目录、登录引用及其他偏好 | `lib/services/security_bookmark_service.dart`、SettingsStorage、凭据迁移等使用 SharedPreferences | 保留字节／值；普通位置已存在的键优先，仅补缺失键 |
| `Library/WebKit/` 等原生插件数据及其他 Library 子项 | macOS WKWebView 及原生插件；首次迁移按容器实际目录生成清单 | 按 Library 分类下的直接子项成组发布；Preferences、Keychains 不直接发布 |
| `tmp/`、其他容器根项、未激活的偏好域 | 外部播放器临时导出、原生临时文件／日志等；不能假定未知文件可删除 | 全部留在经过校验的普通位置归档，同时保留原容器；不将旧临时目录冒充新的系统 TMPDIR |
| Keychain 凭据 | `rust/src/vault.rs` 使用 macOS 默认 Keychain，服务名固定 `com.nipaplay.credential-vault.v1`，当前 keyring 使用 SecKeychain generic password API | 保留服务、account 编码、bundle ID；不搬系统 Keychain，不读取真实凭据 |

容器里的外部目录软链接只复制链接本身，不遍历其指向的媒体目录。失效链接同样保留。容器 Keychains／其他偏好文件保存在完整归档中，不写进全局系统位置。`mpv_session.dart` 使用系统临时目录创建 IPC socket；崩溃遗留的 socket 没有持久文件字节，记录在 `volatile-sockets.plist` 并留在原容器，不复制到归档或活动位置。其他未识别的特殊文件类型会明确失败，不静默丢弃。

### 迁移事务与恢复

迁移目录位于 `~/Library/Application Support/NipaPlay Sandbox Migration/com.aimessoft.nipaplay/v1/`，独立于需要迁移的应用 Application Support 目录，权限 0700。这样迁移自己的状态不会被误判成用户已有的目标数据。

1. 取得跨进程文件锁，序列化本版本的迁移。
2. 流式 SHA-256 检查容器内全部持久文件内容、相对名称、类型和链接目标；复制 `Data` 到 `container-copy`，比较副本及再次读取的源数据。IPC socket 另外索引，原位保留。持久数据在复制期间改变则停止，未发布任何数据。
3. 生成文档活动副本、偏好计划和 `journal.plist`。没有日志的中断表示尚未发布目标，重启可以重新复制快照。日志通过原子写入保存选择、输入摘要及专属暂存文件名。
4. 每组复制到目标目录同一文件系统的专属暂存路径，校验后用 `renamex_np(..., RENAME_EXCL)` 发布。不会覆盖另一进程刚写入的目标。恢复时，已发布目标必须仍与输入摘要一致；未完成暂存可以重新复制。
5. 通过 UserDefaults 写入偏好并读回校验。重启时重新保留普通偏好当前的值，仅补缺失键，避免覆盖两次启动之间新写入的偏好。
6. 验证所有导入目标后，才原子写入完成标志；随后 Flutter 才能启动。进程退出时 OS 释放锁，SIGKILL 不需要依赖异常清理代码。

容器及归档在成功后也不删除。完成标志防止后续正常启动用旧数据覆盖已经变化的新数据库。数据摘要验证的是复制完整性；SQLite 的迁移测试另外运行真实 `PRAGMA integrity_check`。本实现验证了异常及进程强杀恢复，没有声称覆盖断电和存储硬件故障。

### 两边都有数据

不按文件 mtime 判断新旧，也不自动拼接 SQLite／Next 的关系数据。普通位置可能来自用户以前正常使用的非沙箱构建，因此非空的 `Documents/nipaplay` 整组保留；Application Support、WebKit 等实际子目录也按整组保留。直接放在 Library 分类下的 SQLite 文件将 DB、WAL、SHM、journal 视为同一组，防止只导入旧 WAL。空目录只是占位，可导入容器版本；使用 rmdir 确保不会删除其他进程新加的数据。

**结果：已有普通位置继续作为活动数据；冲突的容器版本完整保存在 `container-copy`，原容器也保留，未自动合并的观看历史／Next 数据可供主控或用户明确选择恢复。** 这是保留两份有效版本、避免破坏数据库关系的选择。偏好逐键采用普通值优先、补缺失值的规则；完整源 plist 同样归档。

绝对路径、工作区内容、SQLite 字段及旧 bookmark 不做字符串替换。保留容器使现有绝对路径仍有有效后备；外部媒体路径继续指向用户原文件。迁移是启动基础设施，不新增 Harness Action，也不在引擎尚未启动时开放手动迁移入口。

### 构建环境

没有修改 pubspec、Cargo 或依赖版本。Flutter 自动运行 CocoaPods 时把已有 `macos/Podfile.lock` 的 Erika 0.1.3 刷新到当前已解析的 0.2.1；验收后已恢复原锁文件，交付无依赖文件 diff。这个锁文件基线差异仍存在于仓库与当前解析环境之间。

共享 Erika 解压缓存曾在重建时只剩目录与校验 marker，导致 `error: Erika prebuilt v0.2.1 is missing the macos/macos runtime`。最终构建使用本机已有的同版本 zip 和独立 `ERIKA_PREBUILT_CACHE_DIR`，由插件校验后重新解压；没有修改插件、升级依赖或为测试访问线上服务。

## 3. 验收命令与真实输出

全部 Flutter 命令使用 `~/development/flutter-3.44.6/bin/flutter`、`--no-pub`。原始日志保存在 `/tmp/nipa-next/x2-*.log`。

### 原生迁移测试

```sh
swiftc macos/Runner/SandboxMigration.swift macos/RunnerTests/SandboxMigrationTests.swift \
  -o /tmp/nipa-next/x2-migration-tests
/tmp/nipa-next/x2-migration-tests
```

退出码 0；真实输出：

```text
PASS: fresh installation leaves ordinary data and preferences unchanged
PASS: container-only imports Classic, Next, preferences, bookmarks, caches and support
PASS: both locations keep ordinary data groups and archive the full container version
PASS: empty ordinary directory is a placeholder, rather than a conflicting data group
PASS: direct Library SQLite files preserve an existing database together with its sidecars
PASS: interruption at snapshotCopied resumes on next launch
PASS: interruption at planned resumes on next launch
PASS: interruption at unitCopied:0 resumes on next launch
PASS: interruption at unitPublished:0 resumes on next launch
PASS: interruption at preferencesPublished resumes on next launch
PASS: real SIGKILL at snapshotCopied resumes in a new process
PASS: real SIGKILL at unitCopied:0 resumes in a new process
PASS: real SIGKILL at unitPublished:0 resumes in a new process
PASS: external destination changes stop recovery without overwriting either version
PASS: source changes during snapshot fail before publication and can retry
PASS: preference changes between launches remain authoritative on recovery
PASS: corrupt archive blocks recovery and leaves the original container intact
PASS: real SQLite history survives migration and passes integrity_check
PASS: symlinks are copied as links without traversing external media
PASS: stale external player socket is indexed, remains in the container and does not block migration
All 20 migration tests passed; fixtures were isolated temporary directories.
```

### Flutter 测试

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/macos_sandbox_gate_test.dart test/macos_bookmark_desandbox_test.dart \
  test/security/credential_store_test.dart test/security/backup_credentials_test.dart \
  test/watch_history_database_migration_test.dart
```

退出码 0；日志末行：

```text
00:00 +21: All tests passed!
```

新增测试确认：保存为开启的 Next 在沙箱进程中不可用；开启被拒绝且原偏好保留；非沙箱切换仍持久保存；没有 security scope 的书签路径可返回、不记录假授权、过期书签会刷新。其他测试使用本地 SQLite、内存凭据和模拟偏好，不访问线上服务。

### Dart 分析

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub \
  lib/providers/labs_settings_provider.dart lib/services/macos_process_environment.dart \
  lib/services/security_bookmark_service.dart lib/utils/storage_service.dart \
  lib/settings/pages/labs_settings_content.dart \
  test/next/macos_sandbox_gate_test.dart test/macos_bookmark_desandbox_test.dart
```

退出码 1，唯一问题与 HEAD 基线完全相同，无新增问题：

```text
Analyzing 7 items...
warning • The declaration '_loadActiveResources' isn't referenced. Try removing the declaration of '_loadActiveResources' • lib/services/security_bookmark_service.dart:229:23 • unused_element
1 issue found. (ran in 3.2s)
```

为确认基线，曾把 `git show HEAD:lib/services/security_bookmark_service.dart` 原样放在同一包内临时文件分析，随后删除该临时文件。真实基线输出（退出码 1）：

```text
Analyzing x2_security_bookmark_baseline.dart...
warning • The declaration '_loadActiveResources' isn't referenced. Try removing the declaration of '_loadActiveResources' • lib/services/x2_security_bookmark_baseline.dart:225:23 • unused_element
1 issue found. (ran in 0.1s)
```

其余改动的 Dart 文件无 issue。没有为此次任务删除无关的旧方法或加入 ignore。

### macOS 构建与签名

```sh
ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache \
  ~/development/flutter-3.44.6/bin/flutter build macos --debug --no-pub
codesign --verify --deep --strict build/macos/Build/Products/Debug/NipaPlay.app
codesign -d --entitlements - build/macos/Build/Products/Debug/NipaPlay.app
bash .github/workflows/scripts/verify-macos-entitlements.sh \
  build/macos/Build/Products/Debug/NipaPlay.app
```

全部退出码 0。构建末行与 codesign 真实输出：

```text
✓ Built build/macos/Build/Products/Debug/NipaPlay.app
Executable=~/Desktop/nipaplay-next-wt/desandbox/build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay
[Dict]
    [Key] com.apple.security.cs.allow-jit
    [Value]
        [Bool] true
    [Key] com.apple.security.cs.disable-library-validation
    [Value]
        [Bool] true
    [Key] com.apple.security.device.camera
    [Value]
        [Bool] true
    [Key] com.apple.security.get-task-allow
    [Value]
        [Bool] true
PASS: macOS entitlements contain allow-jit and no app-sandbox
```

`codesign --verify` 成功时无输出。最终构建含原有 CAOpenGLLayer 弃用、脚本每次执行及插件尚未支持 Swift Package Manager 的提示。

Release 配置另外用以下只读命令验证（退出码 0）：

```sh
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Release -showBuildSettings
```

```text
CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements
ENABLE_APP_SANDBOX = NO
ENABLE_HARDENED_RUNTIME = YES
```

macOS composite action 用 Ruby 标准库解析 YAML，再逐段 `bash -n` 验证；权限检查脚本也通过 `bash -n`：

```text
PASS: macOS action YAML and shell syntax
```

### 实际进程沙箱检测

```sh
/tmp/nipa-next/x2-migration-tests --probe-sandbox
sandbox-exec -p '(version 1) (allow default)' \
  /tmp/nipa-next/x2-migration-tests --probe-sandbox
```

两个命令退出码均为 0，同一份原生检测实现真实输出：

```text
sandboxed=false
sandboxed=true
```

### 原生书签、网络、Keychain、播放与加载

```sh
swiftc macos/Runner/SandboxMigration.swift macos/RunnerTests/DesandboxSmokeTests.swift \
  -Xlinker -rpath -Xlinker "$PWD/build/macos/Build/Products/Debug/NipaPlay.app/Contents/Frameworks" \
  -o /tmp/nipa-next/x2-native-smoke
codesign --force --sign - --options runtime \
  --entitlements macos/Runner/DebugProfile.entitlements /tmp/nipa-next/x2-native-smoke
/tmp/nipa-next/x2-native-smoke \
  "$PWD/build/macos/Build/Products/Debug/NipaPlay.app/Contents/Frameworks"
```

独立测试可执行文件使用 hardened runtime 和 Debug 权限；不启动 Runner。临时文件夹、媒体与 Keychain 在测试后清理。输出中的 PASS 行：

```text
PASS: ordinary bookmark resolves and grants normal folder read/write without security scope
PASS: isolated Keychain read/write with com.nipaplay.credential-vault.v1
PASS: loopback network client and server without sandbox network entitlements
PASS: native library loads: rust_lib_nipaplay.framework/rust_lib_nipaplay
PASS: native library loads: libnipaplay_native.dylib
PASS: native library loads: mdk.framework/mdk
PASS: bundled mpv loads, initializes and decodes a local 16x16 video frame
```

Keychain 测试使用与当前 keyring 后端相同类别的 macOS API及指定服务名，存储在独立临时 Keychain；没有访问默认 Keychain 中的用户秘密。网络仅 127.0.0.1；mpv 使用临时 PPM、本地解码和 null 音视频输出。编译测试 helper 有 SecKeychain API 弃用提示，与依赖使用的现有 API 类型一致。

## 4. 问题：需要主控决定的事项

没有新增产品或接口决策需要主控决定。

按任务约定，真实升级留给主控：备份并退出旧版本后，使用真实容器验证全窗口播放、旧媒体库文件夹和原 security-scoped bookmark、签名升级后的真实 Keychain 凭据、Next 恢复及任务状态。本轮只证明本地迁移／门控／原生加载行为，没有执行真实用户迁移或凭据读取。

正式 Developer ID 签名与 Apple 公证没有在本机执行；其流程配置与本地权限检查已完成，实际发布服务验收仍由主控／CI执行。原锁文件与当前解析的 Erika 版本差异已记录，未在本任务调整依赖基线。

## 5. 容器优先（主控决定后的修改）

本节更新前文的冲突决策，最终规则以本节为准：升级前正在使用的是沙箱版本，因此两边都有数据时，容器版本成为活动数据。普通位置的非空数据组完整进入迁移归档，既不与容器组拼接，也不按修改时间选择版本。空目录仍视为占位。

本轮只修改 `macos/Runner/SandboxMigration.swift`、`macos/RunnerTests/SandboxMigrationTests.swift`，并追加本报告。仍在 `next/desandbox`，未 commit、未 push、未修改依赖，未启动 NipaPlay.app，未读取或修改真实用户数据。

### 实现改动

- 删除普通位置非空就保留为活动组的分支。发布容器副本前，先将冲突的普通文档、Application Support、Caches 等数据组归档到迁移状态目录的 `ordinary-archive/<原普通相对路径>`。文档组中的普通 Next、数据库、WAL、SHM、普通独有文件、空子目录及软链接全部保留在归档，活动组只来自容器。
- 直接位于 Library 分类下的 SQLite 文件仍以 DB／WAL／SHM／journal 为一组；归档包含普通位置独有、容器中不存在的附属文件，防止旧 SHM 或 journal 留在活动位置。恢复时若这些已归档的附属文件重新出现，会停止迁移。
- 普通数据先在原文件系统原子改名为日志指定的暂存路径，再复制、校验并发布到归档。归档验证通过后，冗余暂存副本先原子改名进入清理阶段，再移除；清理途中强杀留下的部分副本可继续清理，不会把它误判为原数据损坏。完整原数据始终留在归档中。归档改名、复制和清理阶段都有独立恢复检查；原数据发生变化或归档损坏时停止。
- 普通位置原 plist 原样复制到 `ordinary-archive/Library/Preferences/com.aimessoft.nipaplay.plist`，逐字节校验；普通偏好域的逻辑快照另存为 `ordinary-preferences.plist`。活动偏好通过原有 UserDefaults／cfprefsd 接口整域替换为容器偏好，不再逐键补缺；旧域独有的键不保留。容器没有该 plist 时，活动域为空。
- 日志增加偏好计划摘要与“偏好已发布”状态。偏好写入后、状态记录前强杀，恢复会再次写入完整容器域；状态已记录后恢复不重写已迁移的活动偏好，原有“发布后又写入新偏好”的测试仍通过。
- 跨进程锁、容器快照校验、独占发布、外部目标变化检查、源容器保留及成功后的完成标志继续保留。完成标志仍阻止正常后续启动拿旧容器覆盖已经变化的活动数据。

归档位置相对原迁移状态目录：
`~/Library/Application Support/NipaPlay Sandbox Migration/com.aimessoft.nipaplay/v1/ordinary-archive/`。原有 `container-copy` 和原容器也继续保留。

### 迁移测试与真实输出

更新“两边都有数据”和直接 Library SQLite 冲突测试；原有其余迁移场景继续通过。新增归档阶段异常／真实 SIGKILL、偏好写入与状态记录之间强杀、旧键移除、缺失容器偏好、原数据变化、归档损坏、部分清理等覆盖。共 41 项通过，所有夹具均为临时目录；偏好测试使用夹具中的 plist 持久保存及跨进程读回，不访问真实偏好域。

```sh
swiftc macos/Runner/SandboxMigration.swift macos/RunnerTests/SandboxMigrationTests.swift \
  -o /tmp/nipa-next/x2-container-priority-tests
/tmp/nipa-next/x2-container-priority-tests
```

编译和测试退出码均为 0。真实输出：

```text
PASS: fresh installation leaves ordinary data and preferences unchanged
PASS: container-only imports Classic, Next, preferences, bookmarks, caches and support
PASS: both locations activate container groups and archive every ordinary entry intact
PASS: empty ordinary directory is a placeholder, rather than a conflicting data group
PASS: direct Library SQLite files activate container DB and WAL and archive ordinary-only sidecars
PASS: interruption at snapshotCopied resumes on next launch
PASS: interruption at planned resumes on next launch
PASS: interruption at unitCopied:0 resumes on next launch
PASS: interruption at unitPublished:0 resumes on next launch
PASS: interruption at preferencesWritten resumes on next launch
PASS: interruption at preferencesPublished resumes on next launch
PASS: both locations interruption at ordinaryMoved:0 preserves the archive and resumes
PASS: both locations interruption at ordinaryCopied:0 preserves the archive and resumes
PASS: both locations interruption at ordinaryArchived:0 preserves the archive and resumes
PASS: both locations interruption at ordinaryRetired:0 preserves the archive and resumes
PASS: both locations interruption at unitPublished:0 preserves the archive and resumes
PASS: both locations interruption at preferencesWritten preserves the archive and resumes
PASS: both locations interruption at preferencesPublished preserves the archive and resumes
PASS: both locations real SIGKILL at ordinaryMoved:0 resumes with both versions intact
PASS: both locations real SIGKILL at ordinaryCopied:0 resumes with both versions intact
PASS: both locations real SIGKILL at ordinaryArchived:0 resumes with both versions intact
PASS: both locations real SIGKILL at ordinaryRetired:0 resumes with both versions intact
PASS: both locations real SIGKILL at unitPublished:0 resumes with both versions intact
PASS: both locations real SIGKILL at preferencesWritten resumes with both versions intact
PASS: both locations real SIGKILL at preferencesPublished resumes with both versions intact
PASS: real SIGKILL at snapshotCopied resumes in a new process
PASS: real SIGKILL at unitCopied:0 resumes in a new process
PASS: real SIGKILL at unitPublished:0 resumes in a new process
PASS: external destination changes stop recovery without overwriting either version
PASS: source changes during snapshot fail before publication and can retry
PASS: preference changes between launches remain authoritative on recovery
PASS: before preference publication only container keys are authoritative on recovery
PASS: missing container preference plist clears old domain and archives old plist intact
PASS: changed ordinary group blocks archival without overwriting either version
PASS: partly deleted retired staging resumes using the complete verified ordinary archive
PASS: ordinary-only SQLite sidecar reappearing after archival blocks publication
PASS: corrupt ordinary archive blocks recovery and retains ordinary staging and container
PASS: corrupt archive blocks recovery and leaves the original container intact
PASS: real SQLite history survives migration and passes integrity_check
PASS: symlinks are copied as links without traversing external media
PASS: stale external player socket is indexed, remains in the container and does not block migration
All 41 migration tests passed; fixtures were isolated temporary directories.
```

原始输出：`/tmp/nipa-next/x2-container-priority-tests.log`。

### 模仿维护者 Mac 的夹具

夹具普通文档仅有 `cache`、`compressed_images`、`logs`，总文件字节 24,117,248（23 MiB），目录 mtime 为 2026-07-23；没有 `watch_history.db` 和 `next/`。旧偏好 plist 为 204,936 字节，mtime 为 2026-06-28，包含旧语言和普通域独有键；普通 `Application Support/NipaPlay` 为空。容器夹具含 Classic 历史及配套 WAL、Next 数据及工作区、字体、torrent_session、缓存、偏好和 bookmark 字节。

夹具里的历史／Next 文件使用合成内容，便于直接观察来源；真实 SQLite 的内容与 `PRAGMA integrity_check` 由上述独立迁移测试覆盖。活动偏好按域中的键和值验证，归档旧 plist 按原始字节验证。

```sh
/tmp/nipa-next/x2-container-priority-tests --maintainer-fixture
```

退出码 0，真实输出：

```text
Fixture: /var/folders/7t/363d2swj60v08tg0lbxg9gnc0000gn/T/nipaplay-migration-test-EBD08952-303C-4567-A137-67A588EA50C8 (temporary; removed after verification)
Before: ordinary Documents/nipaplay = 24117248 bytes of cache/compressed_images/logs; mtime=2026-07-23; history=false; next=false
Before: ordinary plist = 204936 bytes; mtime=2026-06-28; locale=en; ordinary-only=June setting
Before: ordinary Application Support/NipaPlay entries=0; container has Classic, Next, support, bookmarks and preferences
After: active history=container-history; WAL=matching-wal; Next=next-facts; workspace=user-tool
After: active locale=zh; bookmark bytes=010203; ordinary-only absent; old-cache absent
Archive: ordinary cache tree (24117248 bytes) and original plist match every entry/type/byte; no merge into active Documents
After: torrent_session=torrent-resume; empty support placeholder replaced; container retained; journal complete=true
PASS: maintainer Mac fixture uses container data and archives stale ordinary data intact
```

观察：缓存目录不再挡住历史和 Next 导入；普通缓存整棵树与旧 plist 均逐项比较名称、类型、链接目标／文件字节，完整进入归档。活动历史、WAL、Next、工作区和偏好均来自容器；旧偏好独有键消失；空 Application Support 占位被容器的 torrent_session 替换。容器保持原样，完成标志为 true。临时夹具在验证后清理。

原始输出：`/tmp/nipa-next/x2-maintainer-fixture.log`。

### Flutter 回归及范围检查

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/macos_sandbox_gate_test.dart test/macos_bookmark_desandbox_test.dart \
  test/security/credential_store_test.dart test/security/backup_credentials_test.dart \
  test/watch_history_database_migration_test.dart
```

退出码 0；真实末行：

```text
00:00 +21: All tests passed!
```

原始输出：`/tmp/nipa-next/x2-container-priority-flutter.log`。`git diff --check` 通过；pubspec、Podfile.lock 和 Cargo 依赖文件无 diff。本轮原生实现已通过独立 Swift 编译与测试，没有重建或启动 NipaPlay.app。

### 需要主控决定的问题

没有。
