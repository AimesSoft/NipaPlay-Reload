# X12：媒体来源配置、登录发起与远程发现

日期：2026-10-11。worktree：`~/Desktop/nipaplay-next-wt/media-sources`；分支：`next/media-sources`。已先读 RESEARCH.md、TEAM.md、CAPABILITY_GAPS.md，并按 X10 的凭据拒绝语义实现。

## 1. 完成了什么

新增 `lib/next/media_sources/`，在 NextCore 注册来源能力与登录/同步执行器，NextRuntime 接上 Classic 的 Provider 与应用根 Navigator。

| Action | 用途 |
|---|---|
| `media.sources.list` | 列出五类已配置来源与最后观察到的连接状态；不读取秘密、不联网。 |
| `media.sources.check` | 对指定来源进行实际认证目录请求，更新成功连接状态；连接或凭据失败返回错误。 |
| `media.sources.add` / `update` | 添加或修改 Jellyfin、Emby、SMB、WebDAV、NipaPlay 共享来源。保存地址与用户名；修改保留密码引用；同一服务器保留其他地址，跨服务器的多地址配置要求另建来源。 |
| `media.sources.remove` | 默认返回删除预览；confirm=true 移除来源配置，保留文件身份、绑定与观看记录。 |
| `media.sources.login` | 自动选择 Jellyfin Quick Connect 或应用内密码窗口；也接受用户主动提供的 password。返回任务 ID；Quick Connect 同时返回验证码。 |
| `media.sources.libraries` / `select` | 获取库、SMB 共享、WebDAV 根目录或共享作品，保存同步选择；Jellyfin/Emby 使用 Classic Provider 的选库与刷新入口。 |
| `media.sources.browse` | 完整浏览库、文件夹、系列、季与条目；Jellyfin/Emby 可递归取得全部可播放条目。共享来源也可传宿主目录路径。 |
| `media.sources.sync` | 递归发现选中的内容，作为可等待、取消和恢复的任务登记统一文件索引。 |

复用 JellyfinService、EmbyService、SMBService、WebDAVService、SharedRemoteLibraryProvider、MediaServerServiceBase 的认证、请求、分页和配置模型；没有第二套媒体服务器客户端。新增的服务入口供 Next 调用，Classic 原来的表单和调用入口保留。

登录窗口从应用根 Navigator 的 overlay 打开。地址、用户名只读且预填；用户只输入密码。取消窗口会请求任务取消，避免把用户取消记成内部失败；并发弹窗取消时只移除所属路由。

浏览/同步调用同一个 IdentityStore.ensureFile，使用 Classic 的 `jellyfin://itemId`、`emby://itemId`、稳定 SMB/WebDAV connectionId 路径及共享流 URL。重复发现复用 fileId，不产生播放进度，不猜作品、季或集身份，不发起弹弹play匹配。来源选择与文件登记不清理历史数据；没有数据库迁移。

没有 commit、push、pub get 或依赖变更。未退出、重启、连接或写入真实 NipaPlay 实例及真实媒体服务器。网络实验只访问题目授权的四台临时服务器和本测试创建的共享回环 fixture；偏好为 Mock，SQLite 为临时目录，保险库为 MemoryVault。

## 2. 决策

1. **配置与登录分开。** Agent 可以先保存来源，再发起认证。密码输入 schema 标记 secret，Harness 日志只记脱敏引用。Jellyfin/Emby 保存会话 token；SMB/WebDAV 和共享 Basic 凭据沿共享保险库保存，不进入来源回执。
2. **Quick Connect 是持久任务。** 发起时立即返回验证码，批准等待最多十分钟。Secret 经 verifiedWrite 进入保险库，任务只保存来源、方法、期限及公开验证码。暂停/中断保留 Secret；完成、失败或取消清理，包括未开始就取消的任务。恢复已提交的认证时验证保存会话。用户直接给的密码只在本次进程内传给执行器，重启后明确失败并要求重新发起。
3. **遵守 X10。** 列表只加载引用。实际连接才读取指定来源的凭据；授权拒绝后的自动操作不能解除 SessionCredentialVault 的抑制，也不自动调用 credentials.retry。存储失败不能返回成功的来源/登录回执。
4. **来源元数据按需加载。** Core 只注册能力；首次来源调用或恢复来源任务才加载 Classic 配置，避免给独立 Core 启动增加插件访问。共享 Provider 与密码窗口由 UI 宿主注入。
5. **使用同一文件登记入口。** 目录发现属于写操作；只列库时不登记根目录中的可播放文件。文件不进入伪造的观看历史；已有绑定、探测修订和观看进度不会因重新同步改变。
6. **同步冻结选库，配置变化报冲突。** 登录、选库、检查和同步检查来源地址/用户名是否仍对应原请求；同步在每次排队浏览真正执行时核对冻结配置，恢复时也不读取替换来源的凭据；正在运行的操作不会把修改后的来源混入原回执。各 Agent 来源操作串行访问 Classic 的当前会话。
7. **共享 Basic 认证仍走 Classic 请求路径。** 用户名单独存偏好，密码使用 `CredentialRef(shared_remote_hosts, basic:<hostId>)`，仅对应 origin/路径的实际请求解析它。显式重登旧 userinfo 来源后把密码移入保险库并清除 URL userinfo；Agent 改地址前也会把该来源的旧 userinfo 密码移入保险库，保留其原 origin；未使用新入口的旧 GUI 路径保留。返回与登记的共享 URL 去除 userinfo。

8. **密码只发往所属服务器。** Agent 修改 SMB/WebDAV 来源时保存密码所属的 host:port/origin，保留引用但跨地址浏览在读取保险库前失败；显式登录绑定新地址。共享 Basic 凭据也保存 origin，修改到其他 origin 后不读取、不发送旧秘密。该约束仅随新入口写入，旧配置默认不改变 Classic 行为。Jellyfin/Emby 更换地址或账号会清除该配置的登录态但保留旧保险库项；多地址配置只有服务器 ID 一致时才允许改地址，防止新会话流向旧服务器。

## 3. 实验

### 四台真实临时服务器

读取 `/tmp/nipa-next/testservers.json`，先断言地址全为回环。实验经过实际 Harness Actions、Classic 服务和现有分页/SMB 原生实现；没有替换四台服务器的网络响应。

执行：

```sh
HTTP_PROXY= HTTPS_PROXY= ALL_PROXY= http_proxy= https_proxy= all_proxy= \
~/development/flutter-3.44.6/bin/flutter test --no-pub --reporter expanded \
  --dart-define=NIPA_X12_REAL=true \
  test/next/media_sources_real_experiment_test.dart \
  test/next/media_sources_test.dart \
  test/shared_remote_library_connection_test.dart
```

Flutter 测试 isolate 使用 Android 的库名。最终实验在 worktree 临时创建 `libnipaplay_smb2.so` 符号链接，指向主仓库已构建的 arm64 `nipaplay_smb2.framework/Versions/A/nipaplay_smb2`；实验后删除。重跑真实 SMB 实验需同样提供此链接，或者在具备原生库的独立实验应用中执行。没有修改原生加载代码或依赖。

Jellyfin 的 Quick Connect 已开启，未修改服务器配置。测试管理员只执行批准验证码；随后执行用户提供密码路径。两次认证均走现有 Authorization: MediaBrowser 头，Jellyfin 12.2 接受了请求。选「番剧」后目录发现六个 Episode，再提交同步；索引中恰好六个 Jellyfin 位置，重入 Classic 定位得到相同 fileId。

真实输出摘录（验证码已属于完成的临时会话；没有密码或 token）：

```text
X12 add jellyfin: {"sourceId":"jellyfin:1791694105530","type":"jellyfin","name":"X12 jellyfin","url":"http://127.0.0.1:8096","username":"nipatest","connected":false,"selectedLibraries":[],"connectionState":"unverified"}
X12 initiate Quick Connect: {"sourceId":"jellyfin:1791694105530","method":"quickConnect","jobId":"source-login-19646efd-ec35-4e6f-af5d-3214c40453cd","code":"922472"}
X12 approve on server: true
X12 Quick Connect task: {"verification":"verified","details":{"sourceId":"jellyfin:1791694105530","connected":true,"method":"quickConnect"}}
X12 initiate user-provided password: {"sourceId":"jellyfin:1791694105530","method":"password","jobId":"source-login-51265cf0-13a0-4516-a0d0-f62217231c93"}
X12 password task: {"verification":"verified","details":{"sourceId":"jellyfin:1791694105530","connected":true,"method":"password"}}
X12 select 番剧: {"sourceId":"jellyfin:1791694105530","selectedLibraries":["28e774baf8f2fd279e7d58da9890a7d2"]}
X12 live connection check: {"source":{"sourceId":"jellyfin:1791694105530","type":"jellyfin","name":"X12 jellyfin","url":"http://127.0.0.1:8096","username":"nipatest","connected":true,"selectedLibraries":["28e774baf8f2fd279e7d58da9890a7d2"],"connectionState":"connected"},"checked":true}
X12 Jellyfin sync: {"verification":"verified","details":{"sourceId":"jellyfin:1791694105530","indexed":6,"fileIds":["file-7a07d14d-a7f7-4e71-bdb4-125bee8501ed","file-5b497d74-e230-49db-b603-0d56114cfd78","file-c93e092d-5a2f-475b-b6f2-06124a8119b5","file-dca1ad82-4102-4610-b2da-7a0d7f016057","file-58788cc0-b8dd-4eaf-b851-13c7ca98b8e5","file-7a132f5d-f917-4faf-9841-51fbc4c1cdb0"],"libraries":["28e774baf8f2fd279e7d58da9890a7d2"],"indexedFilesPreserved":true}}
X12 unified index: files=6, Classic paths reuse same fileIds=true
X12 add emby: {"sourceId":"emby:1791694105842","type":"emby","name":"X12 emby","url":"http://127.0.0.1:8097","username":"nipatest","connected":false,"selectedLibraries":[],"connectionState":"unverified"}
X12 add smb: {"sourceId":"smb:5608d266-bf39-4e83-9faf-aafe01b71034","type":"smb","name":"X12 smb","url":"smb://127.0.0.1:1445","username":"nipatest","connected":false,"selectedLibraries":[],"connectionState":"unverified"}
X12 add webdav: {"sourceId":"webdav:06237cac-2641-4e98-9c38-c95c537435d8","type":"webdav","name":"X12 webdav","url":"http://127.0.0.1:8098/","username":"nipatest","connected":false,"selectedLibraries":[],"connectionState":"unverified"}
X12 NipaPlay loopback fixture: login=succeeded, browse=6, indexed=6, sharedClassicClient=true
X12 browse totals: {"jellyfin":6,"emby":6,"smb":6,"webdav":6,"nipaplayLoopbackFixture":6}
X12 secrets: vaultOnly=true, journal/jobs/preferences/logs contain no password/token=true
00:00 +21: All tests passed!
```

上述片段来自最后一次运行。完整输出保存在本机 `/tmp/nipa-next/x12-final-experiments.log`。其中 Emby、SMB、WebDAV 各有实际 add 和六条 browse 结果，SMB 的库列表是 /media 与 /anime，WebDAV 的库列表是 /anime/ 与 /media/。共享来源使用独立 HttpServer 回环 fixture，经真实 SharedRemoteLibraryProvider 完成 Basic 登录、选库、浏览与同步；这部分不是第五台真实 NipaPlay，也没有访问用户实例。

秘密检查覆盖偏好、完整任务存储 JSON（含 input/checkpoint）、Harness journal、DebugLogService 日志、来源返回值，逐项检查所有实际密码和 token 都未出现；保险库中能读到保存的来源会话。

### 数据约束与 Classic 回归

`test/next/media_sources_test.dart` 的九项检查覆盖：未解析引用的列表与改名不读/改密码；删除预览及移除来源后保留文件 ID/修订；拒绝凭据三次调用只访问 backend 一次；重启不能重放用户给的密码；Quick Connect 暂停/恢复/取消及 Secret 清理；用户取消密码窗口；根 Navigator 弹窗预填/遮蔽/并发取消隔离；共享 Basic 凭据与带路径前缀的 Classic API 请求。新增约束还覆盖 SMB/WebDAV 改服务器保留引用却不读凭据、持久同步任务恢复时拒绝变化的来源且不写文件、共享改 origin 不发请求，以及 Jellyfin 多地址跨服务器修改不动配置、不读 token。相关断言合并在九个测试中。

较大回归范围为 test/next（排除 mesh_integration_test.dart）、test/security，以及 Jellyfin 授权、Emby/Jellyfin 隔离、共享库连接、服务器对话框、服务基类、分页集成、远端路径和 SMB 代理启动：

```text
00:13 +419 ~1: All tests passed!
```

~1 是默认跳过需要明确 NIPA_X12_REAL=true 的真实服务器实验。补完凭据所属地址约束后运行上述回归。最后再加入多地址配置及持久同步恢复约束测试，来源/真实实验/共享 Classic 回归共同重跑：

```text
00:00 +21: All tests passed!
```

来源目录静态检查：

```sh
~/development/flutter-3.44.6/bin/flutter analyze --no-pub lib/next/media_sources
```

```text
No issues found!
```

对修改的生产文件和相关实验测试进行 analyze：没有 error；现有 Emby 未使用方法、MultiAddressServerService 未使用 import 与原有 lint 仍在，实验 print 也产生 info。静态检查完整输出在 `/tmp/nipa-next/x12-analyze.log`，回归输出在 `/tmp/nipa-next/x12-regression.log`。git diff --check 通过。未清理无关 lint。

### 意外与失败

- 初稿把 tasks.wait 的一次状态变化当成最终完成；第一次密码登录实验返回 running，断言失败。改为按 revision 有界等待终态；任务协议保持原样。
- SMB 首轮未找到测试 isolate 所需库；DYLD 环境变量没有解决脚本启动链问题。尝试临时编译 x86_64 库后发现测试进程实际需要 arm64。最终只链接已有 arm64 原生库，完成真实 SMB 认证与浏览。停止的是本批 Flutter 测试进程，不是真实应用。
- 测试最初只进入 /anime 下的第一个目录，走进图片子目录，得到零个视频；改为按返回的目录条目遍历，发现六集。Jellyfin 的「番剧」也返回图片目录，目录类型与空的 SeriesId/SeasonId 保留服务器事实，没有推断归属。
- 初稿启动就加载来源元数据，给无 Flutter Binding 的 Core 测试带来插件依赖；改为按需初始化，11 项 Core/下载运行时检查通过。
- 用户关闭密码窗口最初直接写 cancelled，违反任务必须先有 cancelRequestedAt 的约束；已改为先请求取消，七项来源检查通过。
- 首轮笼统运行 test/next 时，mesh_integration 在 setUpAll 编译本地 Rust 库；停止本批运行，改为排除这项与来源无关的原生集成测试。其余 419 项通过，不声称本批验收 Mesh。
- 窗口集成检查发现 NextRuntime 的 Provider context 在 Navigator 之上；改用应用根 Navigator.overlay.context，并让窗口测试经过同一入口。没有把这一错误留给真实用户实例。

## 4. 需要主控决定的问题

**同类多服务器的文件定位作用域。** Classic 的 Jellyfin/Emby 文件定位目前只有 scheme + itemId，没有 serverId。为了遵守 GUI 与现有持久身份不变，本批沿用这一约定。如果两台同类型服务器出现相同 itemId，统一索引会复用同一文件记录；本次一台 Jellyfin、一台 Emby 的实验没有覆盖这种碰撞。

请主控决定是否把含 serverId 的定位及旧历史/绑定迁移纳入后续批次，并与 X13 播放能力协调。这里没有自行迁移旧定位或改播放解析。除这一已有定位约定外，没有本批集成需要确认的事项。
