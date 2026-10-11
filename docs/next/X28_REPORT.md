# X28：远程与同步能力补齐

日期：2026-10-12。Worktree：`gaps-b`，分支：`next/gaps-b`。未 commit、未 push、未修改依赖。

## 1. 完成了什么

| 用户能做的事 | 本批能力与结果 |
|---|---|
| WebDAV 多端增量同步 | 新增 `sync.status/configure/login/enable/test/run`。直接复用 `AutoSyncSettings`、`AutoSyncService`、Classic 增量仓库和凭据存储。配置、启停进入设置历史；登录、启停和立即同步有任务回执。 |
| 弹弹play 远程媒体库 | `media.sources.*` 增加 `dandanplay_remote`。支持 Classic 单一来源的增改删、用户登录窗口、连接检查、刷新、库列表、搜索浏览、批量查询、播放。 |
| NipaPlay 共享端管理 | 新增 `media.sources.remote_admin.status/folders/connections`。批量管理对端扫描目录，单目录扫描、智能刷新、清理失效目录；管理 WebDAV/SMB 连接、测试、强制刷新目录、请求 Classic 刮削。 |
| Jellyfin/Emby 多地址 | 新增 `media.sources.addresses`：列地址、批量添加/删除/切换/优先级/检查。检查保存连通时间与失败计数，不切换地址；添加核对真实服务器身份。 |
| 下载成功后移除再添加 | 历史成功任务不再独立阻止新下载。只有仍存在对应后端会话时才复用终态任务；旧任务和回执保持原样。 |
| SUMMARY 的来源配置与状态 | `list` 增加地址集合、当前地址、SMB domain、共享端状态/连接时间/错误、弹弹play刷新时间。`check` 可以检查临时配置，保存来源检查失败状态。 |
| SUMMARY 的来源搜索与排序 | Jellyfin/Emby 通过 Classic 请求参数执行库内/跨库搜索及排序；其它来源在当前目录/系列中筛名称。`media.sources.sort` 批量保存 Classic 库排序偏好，记录来源。保留服务器 `UserData/Played`、`ImageTags` 等事实。 |
| SUMMARY 的共享端内容 | 浏览/查询保留简介、封面、身份、进度、时长等远端事实；`query` 支持共享端和弹弹play。新增 `media.sources.play(sourceId,itemId,startPositionMs?)`，在应用内解析真实流地址，并复用 Classic 播放对象。 |
| SUMMARY 的 WebDAV/SMB 刮削 | `media.sources.sync` 可传 `parentIds[]`，从指定目录/库发现文件。新增 `media.sources.scrape(paths[])`，复用 Classic 远程字节匹配；保留既有进度，仅迁移已解除匹配的旧记录。正向识别及进度迁移尚未完成账号条件下的实测。 |

新能力描述说明了必要字段、默认值、批量顺序、部分执行、登录入口、任务读取和取消方法。来源删除去掉 `confirm`，只删除配置和元数据，不删除硬盘文件。登录能力不再接受 `password` 或密码方式；历史密码作业只保留原有恢复识别，不能经当前 schema 提交。

## 2. 决策与代码边界

1. 多端同步与来源发现分开：`sync.*` 操作 Classic 增量仓库，`media.sources.sync` 操作来源文件索引。Agent 自己决定何时配置、登录、启用和同步。立即同步沿用 Classic 的“必须已启用”语义。
2. 配置采用 patch，省略字段保留。修改同步地址/用户名清除旧密码；比较地址时先规范化，避免尾斜线差异误清凭据。类别不能为空，间隔沿用 Classic 的最小 5 分钟。
3. 批量管理按输入顺序执行；后续失败不撤销已经生效的操作。描述明确这一点，每次动作和任务事件仍进入 activity。没有添加调用方自行填写的确认参数。
4. 登录秘密只由用户在 NipaPlay 窗口输入。对端匿名连接无需窗口；非空用户名发起窗口。测试通过后才保存对端连接；取消关闭窗口，重启后不重放密码。
5. 播放接受来源和条目 ID，避免 Agent 复制 CLI 已脱敏的流 URL，也保留 Classic 的共享播放身份与历史上下文。指定起点通过现有播放器端口执行。
6. 检查成功/失败都核对来源是否在请求期间被修改，避免旧请求覆写新配置状态。对端清理先拉取真实目录状态，再调用 Classic Provider 清理，避免依赖过期缓存。

新增实现集中在 [sync.dart](../../lib/next/media_sources/sync.dart)、[remote_admin.dart](../../lib/next/media_sources/remote_admin.dart)。注册和 Provider/播放器附接涉及多人可能共同修改的 `lib/next/next_core.dart`、`lib/next/next_runtime.dart`；变更限于本批注册、排序回调、远程来源播放回调，已撤掉无关格式化。

Classic 路径的修改都是新增入口或保留原默认值：弹弹play地址配置/探测，媒体服务器地址探测及可选搜索排序参数，共享 URL 探测，Provider 排序持久化入口，地址变化事实。`LocalMediaManagementApi` 新增 Next 调用的刮削入口；原有调用的 `migrateProgress` 默认仍为 false。没有改变 Classic 的登录、默认查询、原刮削或下载路径。

## 3. 真实实例实验

脚本：[experiment.py](evidence/x28/experiment.py)。完整、已脱敏的 `nipa describe/call` 输出：[operations.json](evidence/x28/operations.json)。实验在本 worktree 构建的 macOS Debug 可执行文件上直接运行两个隔离 LabProfile，并通过 VM 的 PID 核对实例；没有启动安装版，也没有访问真实用户配置、钥匙串或真实服务器。

实验凭据只由脚本读取 `/tmp/nipa-next/testservers.json`，作为临时配置中的既有 Classic 会话；Agent 没有在能力调用中输入登录秘密。Jellyfin :8096、Emby :8097、SMB :1445、只读 WebDAV :8098 用于来源实验。多端写入另用测试 Docker context 的已安装 `hacdias/webdav:latest` 镜像建立独立临时容器，不修改共享测试服务。弹弹play协议和匿名媒体 WebDAV 使用本次脚本的 loopback fixture，不能据此宣称已验证生产弹弹play服务。

### 3.1 同步、来源记录与增量恢复

实际依次调用 `sync.configure/test/login/enable/run/status`；登录窗口由 `task.cancel` 取消。两端连接同一个临时增量仓库，启用时完成初次合并，再上传播放产生的补丁。对端 Classic SQLite 的读取输出：

```json
{"rows":[["同步测试",4000,8000]]}
```

远程播放后再次同步，对端实际收到新增观看历史；一次完成轮的真实输出为：

```json
{"rows":[["测试影片",2320,8000]],"patchCount":2}
```

`sync.run` 回执包含 `downloadedPatches/uploadedOperations/restoredOperations/createdRepository`，状态包含 phase、次数、最后成功时间和错误。`settings.history` 真实返回 `changedBy: harness_cli`、`origin: harness_cli`，不是 GUI；同时读取了同步阶段的 activity。停用后的 Classic 偏好为 `auto_sync_enabled: false`、间隔 5、类别 `watchHistory/episodeMatches`、最后错误为空。

同步阶段 activity 的实际记录摘录：

```json
{"type":"settings.changed","title":"自动同步 · 设置修改","actor":"agent","origin":"harness_cli","subjectId":"sync.enabled","facts":{"key":"sync.enabled","revision":2,"reason":null,"before":true,"after":false}}
```

窗口截图：[sync-login.png](evidence/x28/sync-login.png)。输入框保持空白，取消后任务进入 cancelled。

### 3.2 两种服务器多地址、搜索与排序

对真实 Jellyfin 和 Emby 各自添加 localhost 备用地址，批量设置优先级、检查、切换，再切回原地址并删除备用地址。两者都保存了成功检查时间和当前地址。检查阶段的返回包含：

```json
{"operation":"check","connected":true,"error":null}
```

上例摘取连通性字段；完整结果含真实 addressId。尝试删除最后一个地址，两种服务器均返回同一个实际约束：

```json
{"status":"failed","error":{"code":"conflict","message":"Cannot remove the last address.","retryable":false}}
```

还通过实际服务器浏览 Sintel、按名字搜索、批量查询详情，确认返回 `UserData`、`ImageTags` 和媒体轨道信息。`media.sources.sort` 后读取本实例的 `jellyfin_library_sort_settings`、`emby_library_sort_settings`，均保存 `SortName/Ascending`，随后读取了 activity 中的来源变化。

### 3.3 弹弹play来源和共享播放

通过能力添加弹弹play fixture，发起 API 密钥窗口并取消，检查、列库、浏览、搜索、批量查询、播放、改配置及删除。查询缺失条目返回 `missingItemIds: ["missing"]`。实际播放回执有 `status: playing`、`hasVideo: true`、时长 8000 ms；截图显示蓝色视频和“测试影片 / 蓝色画面”：

[dandan-login.jpg](evidence/x28/dandan-login.jpg) · [dandan-playing.png](evidence/x28/dandan-playing.png)

共享来源连的是第二个真实 NipaPlay 实例。查询保留其身份 28/2801 和进度；这些是人为准备的测试身份，不是在线匹配结果。指定起点 2000 ms 播放的实际状态摘录：

```json
{"player":"internal","status":"playing","hasVideo":true,"animeId":28,"episodeId":2801,"positionMs":2000,"durationMs":8000}
```

截图：[shared-playing.png](evidence/x28/shared-playing.png)。默认播放对象保留了 Classic 历史上下文；本轮不把这等同于已证明所有 Classic 默认续播副作用。

### 3.4 对端管理、来源失败状态和刮削边界

在对端添加空目录、扫描、智能刷新、移除；再加入目录后由实验脚本移除自己的空目录，通过能力清理。修复缓存问题后实际返回：

```json
{"results":[{"removed":1}]}
```

这是结果字段摘录。完整 state 和对端 `preferences.json` 都只剩原 fixture 目录。

对端匿名 WebDAV 配置任务成功；真实测试和浏览返回 `connected: true`、`X28.mp4`、7153 字节。对端已有 SMB 测试会话也测试成功，并浏览出 `/media/Sintel`；随后通过能力删除两种对端连接。另发起 SMB 用户登录窗口并取消：[peer-login.png](evidence/x28/peer-login.png)。没有替用户输入密码。

本机已保存的 WebDAV/SMB 来源实际完成检查、浏览和从显式 `parentIds` 开始的发现任务。模拟 WebDAV HTTP 503 后，来源检查失败，后续 list 确实返回：

```json
{"connected":false,"connectionState":"failed","error":"DioException [bad response]: null\nError: Service Unavailable"}
```

还调用了本机与对端的刮削入口。两者的真实计数都是：空目录 `total:0, matched:0, failed:0`；非空 fixture 在未登录弹弹play匹配账号时返回 `total:1, matched:0, failed:1`。本机任务 succeeded 表示已完成并核实这组计数，不表示识别成功。本轮没有正向匹配账号，因此不能宣称远程字节识别、匹配成功后的进度保留/迁移已由实验验证。

### 3.5 下载重加：真正重新传输，旧回执保持

用脚本生成 8 秒蓝色视频，真实 BT TCP peer/tracker 提供内容。第一次完成后调用 `download.remove`，保留回执；脚本只删除本轮生成的实验下载文件，再通过能力添加同一 torrent。真实输出摘录：

```json
{"oldReceiptPreserved":true,"bytesBefore":7153,"bytesAfter":14306,"downloadedAgain":true}
```

第二次得到不同 jobId，并再次成功。字节数来自 BT peer 的实际发包计数，不是任务进度推断。应用能力没有删除硬盘文件。

实验最后通过 `state.query(activity)` 读取调用、任务创建/变化/回执、来源增删改等记录；截图：[complete.png](evidence/x28/complete.png)。所有实例按 PID 退出，临时 profiles、容器和配置目录删除。最终清理输出中的 `processesExited`、`profilesRemoved` 均为 true。

## 4. 实验失败与修正

- 初始脚本试图在直接启动的 Debug 二进制里进行 Dart evaluate，但没有 compilation service。改为启动前创建 Classic schema 的实验 fixture，实际能力调用仍全部经 `nipa`。
- 同步配置规范化 URL 时误清已有尾斜线 URL 的密码。已修比较方式，新增数据约束测试覆盖保留凭据、换站清凭据和空类别拒绝。
- :8098 的测试 WebDAV 对写入返回 403。确认是只读服务器权限后改用独立临时可写服务器，没有修改共享服务。Colima 不挂载主机 `/tmp`，实验容器配置改为通过 `docker cp` 传入。
- 对端目录清理返回 0，刷新后才发现 exists=false。能力现先刷新再清理；[修复前输出](evidence/x28/findings-before-cleanup-fix.json) 保留此观察。
- 首次使用负数自定义作品作为共享 fixture，列表成功、详情 HTTP 404。Classic `LocalMediaShareApi` 的详情路由仅接受 `[0-9]+`。按“不改变 Classic 行为”的约束没有修改它，后续使用明确标注的正数测试身份。
- 共享视频开始播放后，`playback.state` 返回 `conflict: This path belongs to multiple sources; use the source browse fileId.`。`IdentityStore.importLegacy` 将 Classic HTTP 历史写入通用 remote scope，而 browse 写入来源 scope；通用 `FileIndexingCapability` 读取播放状态时产生冲突。真实播放器和 `media.sources.play` 已成功，截图与状态回执均保留；没有改其它批次的身份索引模块。

## 5. 回归与交付状态

最终本 worktree macOS Debug 构建成功，使用 Flutter 3.44.6、`--no-pub` 和指定 Erika 缓存。构建生成的 `macos/Podfile.lock` 变化已撤回；没有修改 `pubspec.yaml` 或 `pubspec.lock`。

```text
flutter test --no-pub test/next
01:33 +401 ~4: All tests passed!

flutter test --no-pub <相关 Classic 测试>
00:02 +64: All tests passed!

flutter analyze --no-pub <本批 Next 文件>
No issues found!
```

Classic 测试包含服务器基类、分页、传输、网络服务器对话框、共享连接、torrent 服务/控制器/完成扫描、LAN API 兼容、备份凭据、服务器播放同步 User-Agent。完整命令与验证摘录见 [verification.txt](evidence/x28/verification.txt)。本批新增测试只守下载旧回执/重加数据约束，以及同步配置凭据边界，不以自动化测试替代功能实验。检查 Classic 文件时没有 errors/warnings，存在原有 print 等 info。

## 6. 尚缺的验证与主控事项

尚缺：用户完成秘密输入后的登录保存，生产弹弹play远程服务器，账号可用时的远程正向识别/迁移，所有平台及外部播放器路径。现有证据只覆盖本次 macOS 内部播放器、上述测试服务器和协议 fixture。

需要主控协调的事项：

1. 将“共享播放后通用 playback.state 的重复定位冲突”交给身份索引/一致性批次处理，避免跨来源索引和 Classic 历史互相误认。
2. 决定是否另行授权修复 Classic 的负数共享详情路由。该缺陷也影响 Classic 自定义媒体，本批不能擅自改变它。
3. activity 的通用展示仍由现有渲染器直接拼 actionId/事件类型；新增同步/管理/播放任务标题采用自然短句。本批未改其它批次的 activity 展示，主控需在整合时核对统一的观众文案要求。
