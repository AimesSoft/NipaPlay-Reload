# X32：今天更新、主视觉弹幕与本地观看状态

2026-10-12，Asia/Taipei。worktree `~/Desktop/nipaplay-next-wt/x32-uidata`，分支 `next/x32-uidata`。已读 TEAM、X26、界面数据接口/README、X28 第 4 节及 X23 的实验配置约定。

## 1. 完成了什么

- `home()` 在继续观看后加入 `airing / 今天更新`；空时省略。复用 X29 所用的 Classic 弹弹play日历、详情缓存与客户端，按已接受的作品身份关联，不根据标题猜身份。
- `UiWork.danmaku` 从已有有效弹幕缓存中选择最多六句。与热度使用相同的文件/剧集范围和偏移规则，没有为弹幕短句增加网络请求。
- 新增 `history.mark_watched_batch`，一次接收一个或多个 `{episodeId 或 fileId, watched}`，在 Classic 观看历史事务中写入；看过和取消都刷新原 Provider。Next 能力开启时，Classic 详情页的本地勾选调用同一 Action，已打开的详情页会立即更新。
- 将原键 `labs_use_next_interface` 注册到设置 schema。Agent 和 GUI 都读写实际 NextUiPreference/SettingsStorage 的同一个值，设置历史保留来源，立即切换界面。
- SQLite v12 增加文件别名与合并前的行存档，修复通用 remote 历史与来源范围重复登记。迁移与运行时使用相同合并方法，保留旧 ID、历史观察、编辑、绑定、弹幕和投影回执；重复执行不增加记录。
- 实验发现 Classic 导入的剧集 number 为空时会显示“第 0 集”。界面投影现可读取标题中明确的“第 1 集”等集号；不修改历史或猜测外部身份。

接口 `ui_data.dart` 没有改动。未改会话/定时模块，未新增或变更依赖，未 commit/push。

## 2. 决策

**今天更新采用明确的单集日期。** 收藏来自日历/详情的 isFavorited；在看来自未完成的实际历史和继续观看。只匹配已接受的弹弹play作品身份。单集 airDate 换算成本地日期，今天才出现；只有星期时不推算集号，也不声称今天有新集。集号采用该日历详情的目录顺序，一天多集展示最后一集；日期没有明确时间则只写“今天”。缺缓存且已登录时沿用 BangumiService 的原日历/详情请求，缓存已有时可离线显示。本轮走弹弹play数据，未另写 Bangumi 网络客户端。

日历通过 `StateSources.calendar` 由 GUI 运行时供应，Core 在无 GUI 环境下仍可启动。缓存和本地日期进入 changes 指纹，跨日或日历/详情变化后重新读取。

**弹幕宁可少选。** 只取当前有效绑定缓存，含播放时关闭的轨道。已知时长按 60 桶统计，无时长按 30 秒分段；按时段总弹幕数排序。文本 2–18 字，只接受代码中列出的短反应，例如“画面好美”“音乐好好听”“好治愈”“一起看”，不接收人物/剧情描述。去掉标点、空白后跨作品剧集去重，同一时段最多两句，总共最多六句。相同缓存/范围/偏移只读一次。网址、长串重复字符和允许列表外内容排除；无合适文本就是空列表。这是严格文本选择，不声称识别所有上下文里的剧透。

**本地观看状态保留 Classic 的文件语义。** 只更新 watch_progress、last_position、last_watch_time。看过为 1、位置等于已有时长；取消为 0、位置 0。整批验证，失败整批回滚；相同状态重复调用不改时间。匹配字段、时长、缩略图等保留，成功批次附 before/after 与调用来源。

实际代码中，Classic 原右侧带云朵的勾选是账号同步，不是本地历史写入。因此保留原账号入口，在 Labs 的 Next 能力开启时增加独立本地勾选。Labs Next 能力关闭及单独构建 Classic 详情页时，原行为不变。本地批量能力要求已有文件与 Classic 历史；多集共用一个文件时不能用整文件进度表示独立单集状态，明确拒绝，不制造第二套观看状态。Classic 历史事务与 Next activity 属于两个数据库；先提交历史、再记来源，未声称两个数据库构成全局事务。

**只合并可判定的遗留重复身份。** 范围是同设备、完全相同 locator 的通用 remote 与唯一来源身份；不同服务器范围继续独立，不把相同 URL 当成跨服务器相同内容。首次只有通用 remote 时，来源浏览直接采用它并登记来源范围；来源先到时，历史复用已有身份。

已有两份身份时，来源身份为规范身份，事务内迁移关联行，保留所有历史 location/observation、绑定 ID、证据 ID、弹幕缓存及投影 ID。关联键冲突时保留规范行，旧行完整保存在 `media_file_aliases.archived`；旧文件实体也保留，别名解析供旧任务、引用和读写入口使用。绑定版本取两边最大值，后续版本不会退回旧历史的版本。任务输入、不可变回执与审计正文不改写。失效弹幕绑定不会因合并变为有效绑定。重复合并无新增写入，外键检查为空。

## 3. 实验与真实输出

只直接运行本 worktree 的 Debug 可执行文件，使用临时 `NIPAPLAY_PROFILE`，保持默认安静。没有启动安装版、激活窗口或像素点击，没有访问真实数据或登录钥匙串。临时 CODEX_HOME、公共 CA 副本与 NO_PROXY 都在实验 profile 内；本次是 nipa 能力调用实验，未启动模型对话，也未改用户 Codex 配置。

作品和弹幕是明确制造的 fixture：两段 120 秒蓝色视频、十四集日历，其中第十四集为今天 23:30；不能把它们说成线上内容识别或生产日历验证。

完整真实输出：[初次操作](evidence/x32/operations.json)、[启动迁移补充](evidence/x32/operations-shared.json)、[共享播放](evidence/x32/operations-play.json)、[最终界面投影](evidence/x32/home-final/operations.json)。脚本：[experiment.py](evidence/x32/experiment.py)、[home_check.py](evidence/x32/home_check.py)。下文均为真实返回摘录。

### 今天更新与弹幕

初次 home 顺序为继续观看、今天更新、最近添加。最终投影也确认相同顺序，caption 为：

```json
{"title":"今天更新","kind":"airing","caption":"第 14 集 · 今天 23:30"}
```

经 `nipa call danmaku.import` 导入八条 fixture，包含重复短句、剧情句、重复字符和网址。work() 实际返回：

```json
{"title":"今晚的蓝色天空","danmaku":["画面好美","音乐好好听","一起看"]}
```

“主角下一集会死”、长串“哈哈”和网址均未出现；相同“画面好美”只有一句，最热时段只取两句。最终无弹幕缓存的实例返回 `danmaku:[]`。最后补核对经过运行时供应的日历与明确集号：

```json
{"runtimeCalendar":true,"episodeNumber":1,"emptyDanmaku":true}
```

最终 Next 截图：[next-home-final.jpg](evidence/x32/home-final/next-home-final.jpg)。已目视确认按钮为“播放 第 1 集”，首屏继续观看卡片为“第 2 集 · 剩 2 分钟”。今天更新在继续观看之后，位于这张最终截图的视口下方；在 [初次 Next 截图](evidence/x32/next-on.jpg) 中可见“今天更新”与“第 14 集 · 今天 23:30”，最终 home 返回仍确认该顺序和文字。初次截图的“第 0 集”保留在证据中，已修正；最终截图无此问题。弹幕验证读取的是实际 UiWork 接口，未声称已经验证 UI 的漂浮动画。

### 看过与取消

同一详情页保持打开。nipa 整批标记两集，两次分别返回：

```json
{"status":"completed","result":{"changed":2,"files":2}}
```

独立读取 Classic SQLite 的真实结果，列依次为标题、进度、位置、时长、animeId、episodeId：

```json
[["第 1 集",1.0,120000,120000,32001,3200101],["第 2 集",1.0,120000,120000,32001,3200102]]
[["第 1 集",0.0,0,120000,32001,3200101],["第 2 集",0.0,0,120000,32001,3200102]]
```

`ui.capture` 截图已逐张检查：[操作前](evidence/x32/classic-before.jpg)、[看过](evidence/x32/classic-watched.jpg)、[取消](evidence/x32/classic-unwatched.jpg)。看过时两集右侧是绿色勾选和“已看完”；取消后恢复空心勾选，“已看完”消失。没有重新打开详情页，没有用截图替代数据库回读。

### Next 开关

实际设置返回：

```json
{"key":"labs_use_next_interface","value":true,"revision":1,"apply":"immediate","provenance":{"previousValue":false,"value":true,"changedBy":"harness_cli","origin":"harness_cli","revision":1}}
{"key":"labs_use_next_interface","value":false,"revision":2,"apply":"immediate","provenance":{"previousValue":true,"value":false,"changedBy":"harness_cli","origin":"harness_cli","revision":2}}
```

完整 provenance 的时间和 invocationId 在原操作 JSON 内。`settings.get` 与历史返回同一个值和两次修改，截图实际切换为 [Next](evidence/x32/next-on.jpg) 和 [Classic](evidence/x32/next-off.png)。

### 旧数据迁移与共享播放

使用第二个真实 worktree 实例的 Classic 共享服务器。先正常 browse，再制造 X28 的遗留形态：同 URL 在通用 remote 与来源范围各有一个 fileId，并保留旧证据和用户备注。这里复现的是旧冲突的数据形态；本轮未运行未修复二进制，旧 conflict 原文与播放证据见 X28 第 4 节。

停止本次主实例，将临时数据库置于 v11 后重启。真实回读：

```json
{"distinctFiles":2,"legacyEvidence":true,"userEdit":true}
{"version":12,"distinctFiles":1,"aliasResolves":true,"archivePreserved":true,"legacyEvidenceCount":1,"foreignKeyErrors":[]}
```

规范文件的旧备注实际仍为“旧记录里的备注。”，原始 JSON 转义字符串保留在操作证据中。

启动迁移观察成功后，补跑播放阶段。这次在运行中的临时实例制造重复，用正常身份入口执行同一事务修复，再播放第二个真实实例的共享视频。实际输出：

```json
{"status":"completed","result":{"state":{"player":"internal","status":"playing","hasVideo":true,"paused":false,"seriesTitle":"共享的蓝色天空","episodeTitle":"第 2 集","animeId":32002,"episodeId":3200202,"positionMs":2000,"durationMs":120000,"rate":1.0,"canPrevious":true,"canNext":true}}}
{"distinctFiles":1,"aliases":1}
```

`playback.state` 正常 completed，没有 “This path belongs to multiple sources”；再次导入三条 Classic 历史后仍只有一个文件身份、一个别名。[shared-playing.png](evidence/x32/shared-playing.png) 实际显示蓝色画面与 `00:02 / 02:00`。

### 失败、检查与清理

- 首次测试/构建因缺 `package_graph.json` 提前退出。只读复制同 pubspec.lock 的 sibling worktree 已生成输入，补齐 Swift Package 并重定位；没有 pub get。CocoaPods 自动改动的 Erika lock 已还原。
- 初次全量发现 11 个无 GUI Core/下载测试因日历读取提前使用 SharedPreferences 失败，另一个独立 Classic 详情测试缺 Next Provider。修正为运行时日历供应与可选的 Next 环境后，仅补跑受影响文件。
- 第一轮共享补测使用了重启前的 endpoint 文件，返回 “Cannot connect”。第二轮端点可连接，但 Classic Navigator 尚未挂载，播放返回 “NipaPlay cannot start playback”。脚本现删除旧临时端点，并等只读 `discover.home` 确认挂载，再执行播放。只补跑共享阶段；本地看过、弹幕和开关实验未重复。
- 最后只重验改动过的日历供应/集号投影，未重跑整套实验。原有 audioplayers/gamepad MissingPluginException，以及 Classic fixture 空图片引起的 assets URL 错误保留在日志；本批没有改它们。

验证原输出：

```text
flutter build macos --debug --no-pub
✓ Built build/macos/Build/Products/Debug/NipaPlay.app

flutter test --no-pub test/next              # 全量只跑这一次
02:42 +410 ~4 -12: Some tests failed.

flutter test --no-pub <修正影响的五个 Next 文件>
00:01 +26: All tests passed!

flutter test --no-pub test/next/x32_data_constraints_test.dart
00:00 +4: All tests passed!

flutter test --no-pub <相关七个 Classic 文件>
00:02 +49: All tests passed!
```

所有测试经 TEAM 的 lockf 排队并清除代理。全量的 12 个失败均属于上面两个已修问题，修正后重跑覆盖了这些失败及关联数据约束；遵照只跑一次全量的约束，没有把原全量失败日志改成通过。另有 v0–v11 升级与本批数据约束合计 18 项、UI/设置相关 20 项通过。约束覆盖整批回滚、保留匹配/额外字段、重复写入幂等、保留旧投影回执与绑定版本、外键、不同服务器不误合并。

Next 改动文件 analyze 无 error/warning，保留 12 条花括号风格 info；Classic 详情页保留原有未使用字段等 warning。完整日志位于 [evidence/x32](evidence/x32)。`git diff --check` 通过。

所有实验 App PID：74950、76622、76925、79316、79464、79539、5679、5803、9596，均已按 PID 退出，对应 profile 全部删除。各阶段 cleanup 都实际返回 `processesExited:true, profilesRemoved:true`。用户的 ui-demo 实例未操作。

## 4. 问题

需要主控决定的问题：没有。

目标能力与指定实验已完成。未做生产在线日历、真实番剧弹幕内容和漂浮动画的验证；无既有历史的剧集与多集共用文件的独立观看状态仍按上述 Classic 数据约束拒绝。
