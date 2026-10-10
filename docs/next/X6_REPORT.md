# X6：删除 Next 内置平台弹幕来源与应用内平台登录

2026-10-11；worktree `~/Desktop/nipaplay-next-wt/no-builtin`，分支 `next/no-builtin-platforms`。

## 1. 完成了什么

- 删除 `BilibiliDanmakuSource`、`YoukuDanmakuSource`，包括 B 站 protobuf 解码、WBI 搜索、优酷目录和分钟接口、平台 HTTP profile 与签名桥接。Next 注册的来源现在只有 `dandanplay` 和 `local`。
- 删除整个 `lib/next/sessions/`、`sessions.status`、`sessions.logout`、`ui.open_platform_login`、Core 的会话初始化与恢复、实验室平台登录入口，以及 macOS `PlatformLoginPlugin`、原生窗口和 `nipaplay/platform_login` 通道。没有兼容入口或占位实现。
- 删除仅服务于平台会话的 `DanmakuAccess`、`credentialRef` 弹幕输入与 `sessionAvailable` 来源输出；删除仅优酷分页使用的 `mayHaveMore`。保留来源无关的视频、条目、分段、缓存、绑定、轨道、对齐、偏移、去重、导出与任务能力。
- 弹弹play继续通过 `DandanplayGateway`、Classic 的 `DandanplayHttpClient` 和 `NipaplayServerRouter` 获取；删除了来源声明中直连 `api.dandanplay.net` 的默认值。运行时声明网关域名，账户认证和主备切换继续沿用现有客户端。
- 保留视频旁本地 XML/JSON 的 Classic 发现与解析能力，以及不要求注册来源的 `danmaku.import`。平台身份仍可保存为任意平台，包括优酷和 B 站。
- 更新弹幕 README、种子 `assets/next/harness/AGENTS.md` 及研究纲领中的当前事实；X2 报告注明当时的平台登录入口现已删除。实验 2 的历史轨迹原样保留。

删除前检查了整个 `lib` 和 macOS 注册点的引用。被删来源与平台会话只供 Next 使用；外部引用只有 Next 的实验室入口和对应原生插件。Classic 的弹弹play客户端、本地文件解析、既有登录与共享播放器没有引用被删实现。没有改 Classic 客户端或共享解析器，四项共享轨道回归测试通过。

没有 commit、push、pub get 或依赖修改；没有退出、重启或调用用户正在运行的 NipaPlay。没有改 `nipa`、`state.query`、媒体库实现或 harness 包实现。`media_on_demand_test.dart` 只更换了测试辅助视频常量的一行引用。

## 2. 决策

**持久事实与在线来源独立。** 不新增迁移，不改数据库版本或已发布迁移，不删除、转换或重写历史绑定、缓存、外部视频身份、对齐候选、事件、任务与回执。旧轨道的查询和播放恢复仍从绑定保存的 `cache_key` 读取规范化条目；不需要原来的在线解码器，也不需要来源仍被注册。播放恢复可以读过期缓存。

优酷／B 站的在线定位、获取和 attach 刷新统一因来源未注册返回 `not_found`，失败发生在新绑定或任务提交之前。已经中断的旧获取任务在引擎恢复时同样失败，输入、checkpoint 和已提交缓存保留；不制造成功回执。缓存删除检查跳过已经不存在的来源，保留对其他活动获取任务的冲突检查。

保留现有非会话获取任务的 ID 和缓存键编码：任务摘要原有的空位置继续为 `null`，缓存键的访问域继续为 `public`。这是持久标识的稳定性，不提供会话输入或旧来源执行接口。旧平台缓存键直接按保存值读取，不重新推导。

**钥匙串不清理。** 已有 `next.platform-session/<platform>.v1` 条目保持原样。平台会话代码整段删除，新版本不再读取、更新、使用或主动删除这些条目；没有迁移、启动清理或隐含注销。其余凭据保险库和弹弹play账户能力继续存在。没有读取用户真实平台秘密来做实验。

**保留数据约束测试。** 删除平台协议与会话专属测试；把用于验证分段提交、取消、恢复、修订冲突、导入竞争和偏移的测试改为测试专用 `segmented`／`minutes` 来源。测试替身只返回规范化合成 JSON，没有平台协议或登录逻辑，不注册到应用运行时。

## 3. 实验

所有 Flutter 命令使用 `~/development/flutter-3.44.6/bin/flutter` 并加 `--no-pub`。新回环实验的真实 `HttpClient.findProxy` 为 `DIRECT`。所有数据、账户令牌和平台条目均为合成输入，数据库和原文件均在临时目录。

### 保留能力与旧事实

命令：

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub test/next/danmaku_no_builtin_test.dart --reporter expanded
```

真实输出：

```text
[网络设置] 弹弹play服务器已切换到: http://127.0.0.1:60993/dandanplay
X6 retained: sources=[dandanplay,local]; gateway requests=3; paths=/dandanplay/api/v2/search/episodes,/dandanplay/api/v2/bangumi/7001,/dandanplay/api/v2/comment/7101; authenticated=true; local=1; import=1; reopened playable pools=3; source files removed; restore network requests=0
X6 legacy: platforms=[youku,bilibili]; reopened bindings=2; expired cache rows=2; unchanged fact tables=6; loaded tracks=2; resolve/fetch/attach refresh=not_found (6 calls); new jobs=0; exports=2; offset/displayFold updates=2; original sourceTimeMs=1000; old pending fetch=failed/not_found; checkpoint and cache preserved
00:00 +2: All tests passed!
```

第一个实验使用真实回环 HTTP 服务模拟网关，经现有弹弹play客户端完成搜索、目录、定位及绑定获取，服务端检查路径前缀、认证头和 `withRelated=true`。读取视频旁优酷身份的 XML，另经 `danmaku.import` 交入 B 站身份 JSON。删除两个原文件后重新打开数据库，三个池全部从缓存加载，服务端请求计数仍为 3。

第二个实验落盘两条删除前形状的绑定、规范化缓存和成功任务。其中优酷缓存键包含旧会话引用摘要，B 站视频仍为 `objectType=cid`，缓存时间设为 2025 年。重新打开后使用实际 `DanmakuRuntime` 的来源注册表，比较 `danmaku_bindings`、`danmaku_cache_chunks`、`media_external_objects`、`danmaku_binding_events`、`jobs`、`job_events` 六张表：内容保持不变。查询和播放器条目仍保留平台身份与大整数弹幕 ID；六次拒绝的在线调用后事实表也不变。两条旧轨道可以导出和修改偏移／折叠，源时间仍为 1000 ms。额外恢复一个旧的中断优酷获取任务，观察到 `failed/not_found`，checkpoint、缓存和后续播放恢复保留。

`next_core_test.dart` 另检查实际 Core 注册表只有两个保留来源，三个会话／登录 Action 不存在，fetch／attach schema 中没有 `credentialRef`。`gateway_transport_test.dart` 继续覆盖官方香港／国内网关、当前账户认证、主备切换及登录门槛。

### 完整测试与静态检查

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub test/next test/danmaku_track_timing_test.dart test/danmaku_track_dialog_windowing_test.dart test/danmaku_track_overlay_entry_test.dart test/danmaku_track_popup_barrier_test.dart --reporter expanded
```

```text
01:10 +339: All tests passed!
```

随后对最后调整的 Core schema 断言和合成失败输入单独重测：

```text
00:00 +30: All tests passed!
```

子包没有自己的 `.dart_tool/package_config.json`；直接在其中运行 Flutter 测试最初报 `Couldn't resolve the package 'test'`。使用主仓库已经解析好的 `packages/nipa_harness/.dart_tool/package_config.json`，把包路径转为绝对路径，并仅将 `nipa_harness` 指到当前 worktree，结果写入 `/tmp/x6-harness-package-config.json`。没有解析依赖或更改仓库配置。在当前子包目录运行本机已缓存的 test runner：

```sh
~/development/flutter-3.44.6/bin/dart --packages=/tmp/x6-harness-package-config.json ~/.pub-cache/hosted/pub.dev/test-1.33.0/bin/test.dart --reporter expanded test
```

```text
00:00 +87: All tests passed!
```

改动范围检查：

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub lib/next/danmaku lib/next/next_core.dart lib/settings/pages/labs_settings_content.dart test/next
```

```text
Analyzing 4 items...
No issues found! (ran in 3.1s)
```

也执行了完整 `flutter analyze --no-pub`，删除前后均因既有诊断退出 1。按诊断类型、内容、文件路径比较，忽略删除导致的行号位移：

```text
Before: 5946 After: 5947 New in changed files: 0
New: 1 ('warning', "The path 'img/liquid-glass-demo.png' doesn't exist. Try creating the referenced path or using a path that exists", 'build/unit_test_assets/packages/adaptive_platform_ui/pubspec.yaml', 'path_does_not_exist')
```

额外警告来自测试生成的资产目录，改动文件没有新增诊断。`xcrun swiftc -frontend -parse macos/Runner/MainFlutterWindow.swift` 和 `git diff --check` 均退出 0，无输出。依赖清单、锁文件及其他组员负责的实现目录没有差异。

### 中途的失败与观察边界

- 初次删除 HTTP 公共客户端的 import 时也删去了 `DandanplayLoginRequired` 的类型导入，针对性测试编译失败；恢复现有弹弹play客户端的 import 后通过。
- 回环实验最初被 `TestWidgetsFlutterBinding` 的 HTTP 替身返回 400，服务端没有收到请求。实验改用真正的 `HttpOverrides.createHttpClient`，同时明确直连；最终证据来自真实回环请求。
- 旧任务夹具最初使用不符合 `SqliteJobStore.commit` 的初始修订／事件快照，报 `Snapshot and event must describe the same revision`；修正夹具以满足现有存储约束，没有改引擎或存储校验。
- 子包环境缺少 test 的解析结果，处理方式及最终 87 项输出见上。

这些实验证明删除后的接口、保存和恢复行为，不证明 Agent 已经改用浏览器。没有重启用户应用来重跑实验 2 的真实任务；集成后的同任务 Agent 轨迹仍属于主控的真机实验。

## 4. 问题

需要主控决定的问题：没有。
