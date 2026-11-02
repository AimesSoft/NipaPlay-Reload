# X58：X53 / X54 / X55 合并集成

2026-10-13，Asia/Taipei。worktree `~/Desktop/nipaplay-next-wt/x58-integrate`，分支 `next/x58-integrate`，起点 `d0e70552`。按本次任务授权解析依赖、提交；没有 push，没有启动安装版或实验 GUI，没有运行真实模型对话。

## 1. 完成了什么

依次建立三个 `--no-ff` 合并提交，均以指定的 Co-Authored-By 行结尾：

| 分支 | 合并提交 |
|---|---|
| `next/x53-headless` | `443518e5` |
| `next/x54-catalog` | `90547c33` |
| `next/x55-system` | `dbaed02e` |

保留主分支的 X48 片库、X49 记忆、X50 精简种子/输出预算/信任覆盖、X52 宿主设置、X56 搜索、X57 修复和 Y8/Y9/Y10 界面接线。合入三个分支的后端能力；本轮对 `lib/next/ui/` 的差异为零。

## 2. 冲突与实现决策

### X53

| 冲突文件 | 合并方式 |
|---|---|
| `assets/next/harness/AGENTS.md` | 以 `d0e70552` 的精简版为基础，不恢复分支中的旧长种子。分支新写的远程同契约原则进入 Mesh 族说明；最后只扩充能力族一句话用途列表。保留主分支语言、记忆与授权正文。 |
| `lib/next/agent_endpoint.dart` | 保留 X50 `describeFamily` 和未知入口提示；追加 X53 的动态 Action readiness/effect/remote 事实。族说明不走另一套分派。 |
| `lib/next/headless/core.dart` | UiDataService 改接 X53 的真实宿主 vault，同时保留 X48 LibraryDataService、状态视图、字幕库与 Mesh 合并库接线。FamilyDescriptionCapability 与 AppCapabilities 同时注册；在线客户端、provider 与弹幕来源照 X53 组装。 |
| `lib/next/mesh/runtime.dart` | 保留 X53 的远程覆盖、目录筛选、完整 structuredContent 与文本去重；同时保留主分支经认证的 roles/programExecution 持久缓存，供 X52 离线宿主事实读取。保留 `capability.describe`。Mesh 自身仅开放实际三个 Action，不让 `mesh.set` 等宿主信任配置名称落入放行范围。认证、effect 校验、目标授权及文件 NeedsDecision 不变。 |
| `lib/next/next_runtime.dart` | 同时注册 X50 FamilyDescriptionCapability 和 X53 AppCapabilities。X52 `_startChat`、modelLaunch、模型切换回调以及 X49 memory/recent 接线完整保留，没有恢复旧的聊天组装。 |

X53 条件 import 的纯 Dart ValueNotifier 最初缺 addListener/removeListener，导致现有网关测试被 analyzer 判为错误。补齐相等值过滤及监听行为；Flutter 宿主继续使用 Flutter 实现。旧测试中“远程 settings.set 禁止”的断言按 X53 已授权契约更新，宿主配置无 Action 的断言继续通过。

### X54

唯一文本冲突是 `lib/next/agent_endpoint.dart` 的族说明 import/分派。保留 X50 入口，把 `catalog_family_descriptions.dart` 的五族内容并进共享说明表，删除这个重复文件与 describeCatalogFamily。保留已合入的 X53 单项动态事实。

其余文件自动合并后通过相关约束测试：本地目录保留 local_catalog 关系；移除/恢复保留文件与进度；字幕生命周期、播放观察/重试/导航、台词/弹幕内容读取和图片清除均保留。媒体总说明中“没有外部身份就没有作品”改为允许 `media.entities.put_batch` 建立本地作品，与新能力一致。

### X55

| 冲突文件 | 合并方式 |
|---|---|
| `lib/next/agent_endpoint.dart` | 保留共享族说明入口与 X53 动态事实。把 system/families.dart 的十二族内容合入共享表，删除该文件及重复的 endpoint 分派。 |
| `lib/next/next_core.dart` | X48 LibraryDataService/libraryActions 与 X55 classicScan/resources/events/automatic/storage/desktopSystem/diagnostics、网络/任务订阅全部保留。库与状态接线后同时设置缓存回收所需的 libraryRoots/artworkBusy。保留 X49 memory 和 X52 harnessLocation。 |
| `lib/services/dandanplay_http_client.dart` | 保留 X53 的 dart:async、FutureOr authorization 与 GUI/headless 条件 import；同时引入 X55 NetworkObservations，使用原有客户端与路由器。 |
| `lib/utils/network_settings.dart` | 保留 X53 的 GUI/headless 偏好存储选择，同时接入 X55 SettingsAccess，网络设置变化进入同一注册表来源记录。 |

`next_runtime.dart` 自动合并的 X55 扫描执行器、诊断播放器事实和播放/窗口事件与 X52/X49 接线共存。Mesh 放行列表补入新注册的 events/network/storage/cache/notification/share，目标实际目录、effect 和宿主前置仍决定具体可调用项。

### 唯一能力说明机制与种子事实

所有版本化说明均来自 `lib/next/capabilities/family_descriptions.dart` 的 familyFacts，通过原有 `nipa describe <族>` / capability.describe 获取。AppCapabilities 的 families 也读取同一表；删除 X53 CLI 对 app/danmaku 的专用 describe 路径，远端一律走共享 capability.describe。三个新增说明文件均删除，没有第二套事实表或族分派。

| 来源 | 内容的最终位置 |
|---|---|
| X53 种子唯一新原则 | `mesh`、`media.mesh_files`：远程写与本机同契约，宿主信任/秘密登记不开放，删除/覆盖保持预览和决定。旧的“设置不可远程修改”等限制说明同步更新。 |
| X53 app/danmaku 描述 | `app`、`danmaku`：宿主支持与可用前置、credentialRef、readOnly 作用域、无 Classic 投影、批量部分成功、legacyRecovery。 |
| X54 领域说明 | `media`、`media.entities`、`subtitle`、`playback`、`danmaku`：本地目录、可撤销移除、字幕副本、观察与命令、时间线/台词、图片清除。X54 没有向种子新增细节。 |
| X55 系统说明 | `download.limits`、`task`、`events`、`network`、`storage`、`cache`、`diagnostics`、`app`、`notification`、`share`、`window`、`media.indexers`。X55 没有向种子新增细节。 |

种子最终 **9,712 UTF-8 字节**（小于 10,000，也小于 10 KiB）。仅在用途列表给 media/subtitle/task/app 补目录、台词、控制、能力/更新等词，以及三行新系统能力族索引；没有把 Action 参数、行为协议或限制细节写回种子。X50 CLI 输出预算及 harness 信任覆盖未改。

### 设置注册表与事件

核对 Y8 的五个缺口：

- 取值显示名：注册表新增与实际 enum 对齐的 `enumNames`；动态 enum 也按当前值生成，中文显示名与技术名称由后端 presentation.dart 提供，支持 settings.describe 字段投影。
- 路径类型：为 harness、下载目录、截图目录、字幕字体目录标 `format: directory`；外部播放器、弹幕字体、背景图标 `format: file`。保留实际值及验证，不把 WebDAV 服务器路径当本机文件。
- 来源：`harness_cli` 和 `harness_cli:*` 写入 `changedBy: agent`，原始 origin 保留。旧行读取时归类，不迁移或改写原持久记录；用户 GUI 修改后仍为 user。
- 启动时清理弹幕缓存：X55 已注册 `storage.clearDanmakuOnLaunch`，沿用 Classic 行为，Next 导入的唯一副本不回收。
- 设置变化事件：X55 GUI 的 registry.onChanged → settings.changed → hooks/followup 持久日志已接通；补齐 headless 同一接线与 events 能力。事件附来源、理由、revision 与 invocationId，失败/冲突不发已提交事件。

Y8 通用生成继续消费同一 schema/enum；新增键按既有编排规则生成，路径标记直接由既有 UiSetting.fromRow 识别。Y8 原有显示名过渡表、刷新方式未修改；此次补齐后端元数据和可订阅事件，没有修改界面代码。

### 字幕匹配合并

X47 `subtitle_match_io.dart` 是 Classic Dart 回退算法的完整复制；X46 已让 `lib/utils/subtitle_file_utils.dart` 通过 match_native.dart 在 Flutter 使用 Rust、纯 Dart 使用 match_native_io 的无原生回退。两份算法的实际差别只是原生入口和外部字幕 URI 规范化。

无界面 companions_io 改用共享 subtitle_file_utils，删除 373 行重复匹配代码。保留 match_native_io 的纯 Dart 选择和 match_native_flutter 的 Rust 可用时加速，不改变 Classic 的原生/回退选择。保留原附件发现、字幕分数、季/集拒绝、格式优先、大小写扩展名、VobSub bitmap/header/配对规范化与文本 .sub 行为。

新增 `subtitle_match_integration_test.dart`：实际启动同版本纯 Dart 解释器（仅计算，不启动节点），对比 Flutter 回退结果和分数，覆盖中文、字幕组噪声、错季、错集、不同作品；附件回归检查 SRT/VTT、IDX/SUB 大写配对、MicroDVD 文本 SUB、孤立 IDX，以及源文件内容保留。Classic 字幕测试同时验证共享实现没有退化。

## 3. 验证与观察

依赖只执行一次指定的 `PUB_HOSTED_URL=https://pub.dev ~/development/flutter-3.44.6/bin/flutter pub get`。后续 Flutter analyze/test/build 均加 `--no-pub`；Dart AOT 用显式 `--packages=.dart_tool/package_config.json`，不执行 pub。没有改 pubspec.yaml/pubspec.lock；CocoaPods 生成的 Podfile.lock 差异恢复，保留当前既有依赖生成的 GeneratedPluginRegistrant.swift。

所有 Flutter 测试经 `lockf -k /tmp/nipa-next/flutter-test.lock` 排队，移除六种大小写代理变量并设置回环 NO_PROXY。构建、原生编译与生成物均在本 worktree；没有在主仓库构建。

| 验证 | 结果与证据 |
|---|---|
| X53 相关测试 | **51 通过，2 跳过**；[x53-tests-final.txt](evidence/x58/x53-tests-final.txt)。覆盖 headless 在线事实、远程回传、program、族说明、记忆、宿主设置与 Classic 网关故障转移。 |
| X54 相关测试 | **68 通过**；[x54-tests.txt](evidence/x58/x54-tests.txt)。 |
| X55 相关测试 | **89 通过**；[x55-tests.txt](evidence/x58/x55-tests.txt)。 |
| 设置/字幕整合 | 初次组合 **36 通过、1 失败**；失败是新测试误以为 registry.describe 按 keys 输入顺序排列，改为按 key 取行。其余字幕/headless/系统/Y8 测试通过；最终设置测试 **16 通过**。见 [integration-tests.txt](evidence/x58/integration-tests.txt)、[settings-tests-final.txt](evidence/x58/settings-tests-final.txt)。 |
| analyze | `flutter analyze --no-pub lib/next bin test/next`：**0 error，0 warning，209 info**；[analyze-final.txt](evidence/x58/analyze-final.txt)。默认 analyzer 将 info 也计入退出码，exit 1 来自 info；没有批量格式化或清理无关 lint。 |
| 完整 Next 测试 | **582 通过，7 跳过，0 失败**；完整目录只跑一次。[next-full-tests.txt](evidence/x58/next-full-tests.txt)。跳过项要求显式 Dart/AOT/实验路径，没有把它们报告为已执行。最后的补充显示名只重跑相关设置测试。 |
| Classic 字幕 | `test/subtitle_*` 三个测试文件、remote_subtitle_cache、emby_external_subtitle_selection：**34 通过**；[classic-subtitle-tests.txt](evidence/x58/classic-subtitle-tests.txt)。 |
| headless AOT | **成功**；[headless-aot.txt](evidence/x58/headless-aot.txt)。最终产物 `build/headless/nipaplay-headless`，未运行该二进制。 |
| headless native | 离线 locked 构建 **成功**，16 条 Rust warning；[headless-native.txt](evidence/x58/headless-native.txt)。不将原生 warning 混称为 Dart analyzer warning。 |
| macOS Debug | **成功**；[macos-debug-final.txt](evidence/x58/macos-debug-final.txt)。产物 `build/macos/Build/Products/Debug/NipaPlay.app`，未启动；Xcode/原生插件存在编译 warning，不影响构建成功。 |

macOS 第一次构建失败：[macos-debug.txt](evidence/x58/macos-debug.txt)。Erika v0.2.1 原有临时缓存有已校验 ZIP 和 marker，但 unpacked 只有 marker，没有 dylib。按插件自带脚本在本 worktree `build/erika-prebuilt-cache` 重新下载、验证 SHA-256 和解包，成功生成运行库；未修改依赖或用户缓存。见 [erika-runtime.txt](evidence/x58/erika-runtime.txt)。随后以该缓存目录重试 Debug 构建，不启动应用。

完整测试中的回环 TLS/媒体夹具使用其自身临时目录及清理逻辑。host_settings 的既有测试启动真实 Codex app-server，模型响应由回环合成 SSE 提供，没有访问真实模型或账号。未额外新开 GUI 实例、未打印或保存真实秘密。保留原三个分支历史报告及其原始边界，不把本次自动化检查宣称为新的真实功能实验。

## 4. 需要主控决定的问题

没有。
