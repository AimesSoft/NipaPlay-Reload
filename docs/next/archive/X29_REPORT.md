# X29：发现数据与界面入口

2026-10-12，worktree `gaps-c`，分支 `next/gaps-c`。未 commit、未 push。

## 完成了什么

已阅读 TEAM、RESEARCH、覆盖复审 SUMMARY、m5-discover，以及 m8-system 的界面入口部分。本 checkout 的 SUMMARY 没有任务书提到的同名“界面和对话框的打开动作”小节，本批按缺失表 #8/#27、部分覆盖表和 m5/m8 的具体入口落实。

| 范围 | 实现 |
|---|---|
| 标签、高级搜索及配置 | `discover.search_config/search/search_batch` 直接复用 `SearchService`，保留评分和完整作品字段；返回全部服务结果，不依赖界面加载更多。配置返回有效年份、类型、标签和排序。 |
| 排行榜 | `discover.trending/trending_batch` 复用 `TrendingBangumiService`，支持三种榜单、三种周期及本季/上季；返回统计日期、排名、热度和增长指标，可强制刷新，最多 50 条。 |
| 日历 | `discover.calendar` 复用 `BangumiService.getCalendar`，返回完整名单、今日条目及八个星期分组（含未知）。 |
| 推荐与首页 | `discover.recommendations` 返回官方每日全部分组；`next:true` 调用 Classic 换组逻辑。`discover.home` 返回完整已加载首页快照；`discover.refresh` 等待 Classic 推荐、最近内容、日历、排行榜、回顾、远程 Resume 和本地历史刷新。 |
| 季度回顾 | 首页快照包含名单、开播日期、评分、短评时间与排序；新增 `appearance.quarterlyReviewSort`，使用原持久键和五种原排序。`ui.open(dialog:quarterly_comment, reviewAnimeId:…)` 发起原 Bangumi 编辑器。 |
| 设置与主入口 | `ui.open` 支持设置的 17 个标准分页、WebDAV 快捷设置、新番窗口、下载、账号及当前可见主页面；媒体库可指定实际可用分区。 |
| 常用对话框 | 搜索、观看历史、完整榜单、榜单筛选、插件市场/README、依赖版本、UI 预览、构建信息、日志、四类连接表单、账号登录/注册、赞赏码。 |
| 详情入口 | 正数/自定义负数 `animeId`；Jellyfin/Emby `serverItem`；共享/弹弹play远程 `sourceItem`；本地/WebDAV/SMB `libraryItem`。媒体库卡片入口复用原点击逻辑，包括最近打开、NEW 基线和剧集上下文。 |
| 系统入口 | 五种关于页固定链接及二维码；Harness/日志目录使用原系统打开服务。视频文件/移动端相册选择复用 Classic 选择与播放流程。 |
| 回执与 activity | `ui.open` 返回请求目标和实际界面，设置返回实际分页，媒体库分区不可用时返回实际回退分区与 `matched:false`。新增 `ui.close`；界面和发现调用进入原 invocation journal，并投影到 activity。观众标题使用短句。 |

所有新参数、默认值、登录前提、范围组合和不可用语义都在运行时 `nipa describe` 中；保存的描述见 [x29-evidence](x29-evidence/)。未增加密码参数、确认参数或删除硬盘文件的操作。

## 决策

1. 数据查询直接调用 Classic 客户端；界面有状态的换组、刷新和排序通过小接口访问现有 State，不创建另一份首页缓存或持久模型。首页快照和换组需要已挂载首页，Agent 可先 `ui.open {"page":"home"}`。
2. 搜索和排行榜提供批量原语，每批 1–20 个请求；先校验全部输入，再发请求，按输入顺序返回每项结果或错误。标签搜索与高级条件互斥；评分次序、榜单维度组合在边界验证。
3. 不把服务完成当作网络新鲜度保证。Classic 本身会回退缓存或把错误保存在页面状态；描述和结果沿用这些语义。忙碌或播放器活跃时首页刷新返回 `refreshed:false`。
4. 界面回执观察已挂载页面、当前路由和实际渲染的设置/媒体库分区。外部网页、文件夹只报告系统接受请求；原生选择器只报告已发起，均带 `visibilityVerified:false`，不声称 Flutter 已观察到系统窗口。
5. 新番页面原来在 `initState` 读取本地化，真实实验中无法渲染。新增默认关闭的 `deferInitialLoad` 参数，仅 Next 入口启用，并包装现有窗口 Scaffold；Classic 原入口和默认初始化时序不变。
6. 登录表单仍由用户填写。实验脚本使用提供的专用测试凭据预置隔离夹具登录态，不通过 Agent 密码输入能力；秘密只存在临时实验目录，未写入报告、回执或证据。

## 真实实验

仅构建本 worktree，使用 Flutter 3.44.6、`--no-pub` 和指定 Erika 缓存，直接运行本 worktree 的 Debug 可执行文件。实验配置为 `NIPAPLAY_PROFILE=x29-discover-1791740161`。所有 `nipa` 均从该配置的 Harness 调用，访问回环地址时取消代理环境变量。截图记录包含 PID、可执行路径和实验配置名，未按应用名寻找或启动应用。

### 发现数据

命令示例（实际调用，不是测试替身）：

```sh
./nipa call discover.search_config '{}'
./nipa call discover.search '{"tags":["机甲"]}'
./nipa call discover.search '{"keyword":"高达","year":2025,"minRate":7,"maxRate":10}'
./nipa call discover.trending '{"kind":"allHot","range":"week","forceRefresh":true,"limit":50}'
./nipa call discover.calendar '{}'
./nipa call discover.recommendations '{"next":true}'
./nipa call discover.refresh '{}'
```

未登录时，搜索、配置、榜单和日历沿用 Classic 登录门槛；每日推荐仍可读。预置专用弹弹play测试登录态后，真实官方服务结果如下。计数是对保存的真实 JSON 的投影，完整原输出见 `authenticated-00…10`。

| 调用 | 观察 |
|---|---|
| 配置 | 7 类类型、164 个标签、7 个排序，年份 1971–2027。 |
| 机甲标签 | 100 个作品，包含评分和作品信息。 |
| 高达 + 2025 + 7–10 分 | 0 个作品，正常空结果；没有虚构候选。 |
| 搜索批量 | 两项按请求顺序返回。 |
| 全站热播周榜 | 50 个排名记录，完整榜单窗口也显示“共 50 部”。 |
| 排行榜批量 | 全站飙升月榜、新番热播上季两项均返回。 |
| 日历 | 108 个作品、8 个星期分组、今日 10 个。 |
| 每日推荐 | 2026-10-12，5 组，每组 5 个；生成时间 `2026-10-11T16:02:22.993Z`。 |
| 换组/刷新/快照 | 活跃分组 0 → 1 → 2；刷新 `refreshed:true, loading:false`，随后快照读到同一分组。 |

[完整数据输出](x29-evidence/authenticated-06-discover.calendar.json)、[观察投影](x29-evidence/discovery-observations.json)、[榜单截图](x29-evidence/capture-final-30.png)。

### 打开界面并观察实际状态

逐项调用了所有设置分页及上述常用对话框。`ui-final-00…17` 的 18 个设置目标全部返回实际目标分页；新番、下载、账号、媒体库、本地库/管理均调用成功。无连接时远程分区没有假装打开；后续 Emby 服务就绪后返回实际 `emby` 分区。账号登录/注册只观察打开回执，未提交密码，未交付含测试账号背景的截图。

修复后新番的 [实际截图](x29-evidence/confirmed-new-series.png) 可见日历卡片。五种关于页二维码均打开；[仓库二维码截图](x29-evidence/entrance-repository-qr.png) 可见原二维码。插件市场刷新获取 7 个插件后，用市场 ID `better_danmaku_filter` 打开 README，[截图](x29-evidence/readme.png) 可见真实文档正文。最初误用了本地内置插件 ID，回执为不可用；没有把市场和本地 ID 混为一谈。

本地库夹具包含《摇曳百合》两条临时历史，文件仅用于详情观察，未播放。真实输出：

```json
{"status":"completed","result":{"opened":true,"interface":"classic","target":{"libraryItem":{"source":"local","animeId":8353}},"actual":{"kind":"library_detail","source":"local","animeId":8353,"episodeContext":true},"reason":null,"message":null}}
```

Classic 持久值读取（仅选择这些非秘密键）：

```json
{
  "flutter.library_new_content_baseline_v1":"{\"local\":{\"8353\":2},\"__initialized_local\":true}",
  "flutter.library_last_open_time_v1":"{\"local\":{\"8353\":1791742120127}}",
  "flutter.quarterly_review_sort_v1":"ratingHigh"
}
```

Emby 使用提供的回环测试服务器，`serverItem` 打开了 Sintel，实际显示封面、简介和 14 分钟时长，[截图](x29-evidence/confirmed-emby-detail.png)。服务刚恢复时分区不可用的回执与实际回退相符：

```json
{"opened":false,"interface":"classic","actual":{"kind":"page","page":"media_library","subpage":"local_library","matched":false},"reason":"目标界面当前不可用。","message":"暂时无法打开。"}
```

就绪后再次调用：

```json
{"opened":true,"interface":"classic","actual":{"kind":"page","page":"media_library","subpage":"emby","matched":true}}
```

以上两段是原回执字段摘录，完整输出分别为 `confirmed-emby-library.json` 和 `confirmed-emby-ready.json`。单独的 `media.sources.check` 因实验源尚未被该枚举发现返回 `not_found`；没有据此宣称检查成功，也没有改动其他批次的来源实现。

`system:harness/logs` 返回系统接受的实验目录路径；官网链接返回 `webpage_request`。视频选择入口返回：

```json
{"opened":true,"interface":"classic","actual":{"kind":"native_picker_request","dialog":"video_picker","requested":true,"visibilityVerified":false}}
```

按实验 PID 查询系统窗口列表，确实出现 `title:"Open", onscreen:true` 的原生窗口（[记录](x29-evidence/native-picker-windows.json)）；Flutter 截图不包含它。向该 PID 发送 Escape 后窗口仍在，不能声称取消成功，随后按 PID 结束该实例关闭选择器。选择器期间刷新正确返回忙碌；重启临时实例后再刷新返回 `refreshed:true, loading:false, reviewSort:"ratingHigh"`（[输出](x29-evidence/post-picker-refresh.json)）。桌面相册入口返回不可用。

### 来源、activity 与意外

排序通过 `settings.set` 写入。最初使用了错误枚举 `ratingHighest`，schema 明确返回五个合法值；按描述改用 `ratingHigh` 成功。来源记录包含：

```json
{"previousValue":"airDate","value":"ratingHigh","changedBy":"harness_cli","origin":"harness_cli","reason":"X29 临时配置，验证季度回顾排序来源与 Classic 一致","invocationId":"inv-1791741681214819-20","revision":1}
```

`settings.history`、Classic 持久值和 `discover.home.reviewSort` 一致。activity 的 [实际查询](x29-evidence/setting-activity.json) 包含 `settings.changed`、同一 invocation 和来源。界面/发现回执也能读到“界面已打开”“窗口已关闭”“发现内容已载入”“已发起视频选择”“已请求打开网页”等短句（[输出](x29-evidence/confirmed-activity-final.json)）。

实验还发现快速关闭详情再切页会把根页面弹掉：Next 适配器先退到根，又调用旧详情的 `popIfOpen`。已移除页面切换的重复退栈，并只对当前可见详情执行替换。复测正数详情 → 关闭 → 负数详情 → 关闭 → 本地库 → 卡片详情 → 关闭 → 首页全部成功，根界面仍在（`route-retest-00…07`）。负数 ID 实验只证明详情入口接受自定义 ID，没有据不存在的夹具宣称自定义信息加载成功。

## 验证及边界

最终执行：

```sh
flutter test --no-pub --concurrency=1 test/next
```

结果：**402 passed，4 skipped，All tests passed**。新增自动化测试只守输入约束、批量请求执行前验证和 UI 目标互斥；设置 REST 夹具补上新持久键，不把自动化当功能成立的证明。

Classic 相关回归：标签搜索、延迟搜索、排行榜、季度回顾缓存/短评/外观设置、关于页、Adaptive 设置、大屏设置焦点、服务器表单、媒体库卡片排序/分区顺序/电视媒体库，共 **70 passed，1 failed**。失败是原 `quarterly_review_cache_test.dart` 的 `initial collections are paced, deduplicated and resume after restart`：测试把 probe 时间设为当前季度第三个月 28 日，`recordCollection` 写真实当前时间，随后超过既有 14 天窗口，预期 null 实际得到 100000。本批未修改该测试或 `QuarterlyReviewCache`，未改变 Classic 缓存行为。未把这项失败隐藏成“全部通过”。

macOS Debug 构建成功；改动文件 analyze 无 error/warning，有 22 条 info（短 if 的花括号及已有 import/final 提示）；`git diff --check` 通过。初次完整并发测试曾在构建负载下触发两个 3 秒 hook 超时，串行完整重跑通过。初次新排序 REST 夹具未覆盖原键，已补上。

生成环境原先缺 package graph 和生成 Swift packages，只补生成文件，未运行 pub get。Flutter 自动 pod 安装改动的两条 Erika lock 记录已恢复原值，交付不包含依赖文件变更。

尚未取得完整成功实验的条件：真实连接的 NipaPlay 共享/弹弹play远程/WebDAV/SMB 卡片详情、Jellyfin 详情、Bangumi 已登录且有回顾名单的短评窗口，以及手机/电视布局和相册权限。共享/远程无夹具连接、回顾编辑无 Bangumi 登录时均如实返回不可用；未触碰用户真实服务器。移动端相册入口是复用已有路径的实现，不能用 macOS 实验宣称跨平台验证完成。

本批不改变源配置/同步、播放管理、删除确认或窗口管理策略。源编辑、多地址/同步配置入口属于并行批次；详情内部操作、背景/备份/种子等选择器不在本批发现入口实现中。集成时仍需核对其他批次提供的相应能力，不能把本报告当成全应用对话框的穷尽清单。

## 共享文件与清理

主要新增文件为 `discover_capability.dart`、`classic_home.dart`、`ui_targets.dart`、`dashboard_home_access.dart`。共享文件 `next_runtime.dart` 仅增加注册/回调；`classic_settings.dart` 仅增加回顾排序；`activity.dart` 仅增加界面/发现回执投影和短句。Classic 文件仅增加访问接口、渲染选择观察、推荐日期元数据和 Next 专用的新番延迟加载选项；`video_upload_ui.dart` 只增加既有选择方法的接口。合并 A/B/D 时注意这三个 Next 共享文件和视频上传接口。

最终清理结果记录在 `x29-evidence/cleanup.json`：按控制文件中的精确 PID 终止实验实例，删除该实验配置（含登录态、凭据 vault、历史和临时视频），并删除可能含认证日志的临时 app 日志。提供的测试服务器和凭据源不动。交付的 JSON 经过 nipa 脱敏，并用夹具秘密做了本地匹配检查；账号截图未交付。

## 需要主控决定的问题

没有。上述尚未验证的环境条件需后续集成实验补证，不要求改变本批能力语义。
