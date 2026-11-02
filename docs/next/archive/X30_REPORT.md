# X30：安全与一致

2026-10-12；worktree `gaps-d`，分支 `next/gaps-d`。依据 TEAM、RESEARCH 和覆盖复审 SUMMARY，以及 m1–m8 的相关反方向风险、待确认项。本批采用任务书给出的删除规则，覆盖旧研究文档中的 destructive 默认预览规则。

## 完成

| 项目 | 结果 |
|---|---|
| 删除硬盘文件 | `download.delete`、`plugins.delete` 返回独立 `disk_deletion` 任务；应用弹出“删除文件”，任务进入 `waiting_user`。只有应用对话框的“删除”按钮允许底层删除。拒绝为 failed，消息“用户没有同意删除”，有 verified 未删除回执。支持 task.wait、取消和 followup.register。 |
| 批量与重启 | 一次确认覆盖输入的整批。部分项删除失败时任务失败，保留逐项结果；等待任务重启后重新询问，已经进入 deleting 的中断任务不自动重放。没有供 Agent 提交批准的 Action、checkpoint 或确认参数。 |
| 其余 destructive | 去掉 `media.sources.remove.confirm` 和 HTTP 的 execute 预览关卡；MCP、HTTP、本机 CLI、Mesh CLI 采用同一能力层。`--execute` 兼容旧 CLI，已没有审批作用。删除连接、恢复备份、清空内存日志等直接执行并记 activity。 |
| 备份恢复 | `.npb` 在凭据解析和任何写入前过滤设置 denylist。注册设置恢复经过同一个 SettingsRegistry / Classic setter，不能借恢复绕过参数范围、快捷键冲突、性能警告和外部播放器准备。凭据恢复只接受本机已有引用，跳过新的明文登录秘密。`.nph` 只解析历史字段并更新历史及 video_positions，不存在任意设置写入入口。 |
| 弹幕 | 空文件不能替换已有池；Next 挂载触发 Classic `danmakuLoaded` 插件事件；解绑弹弹play轨道只剥离管理绑定，保留 Classic 轨道和弹幕。 |
| Mesh | TLS 验证后的 deviceId 进入 Classic RemoteControlAccessGuard；每次 RPC 检查 Classic 接收开关和可信设备，未知设备由 Classic 授权界面处理，撤销信任立即有效。拒绝原因传回发送端。保留原有 Mesh 能力白名单。 |
| 参数与 Classic 交互 | GitHub 代理要求 HTTP(S)、有效主机、末尾 `/`，请求 Classic 插件索引得到 200 才保存；空字符串关闭。单集状态仅 state=2。字号为 0 自动或 12–60；Titan 上限 1000、偏移 ±100；进度条仅五个预设颜色，模糊仅 Classic 档位。快捷键冲突显示替换/取消。时间轴预览显示性能警告。启用外部播放前检测 mpv 或打开选择器，取消时保持关闭。 |
| 合法值被误限 | seek 步长用 Classic 当前视频的动态范围；取消人为加在手动弹幕偏移和单轨偏移上的 ±30s、±2h 上限。 |
| 安装时隐式删除 | 插件更新若改变标识会删除旧脚本，Next 安装路径禁止这一隐式删除；先调用 plugins.delete 并等用户确认，再安装新标识。同标识更新继续复用 Classic 写入。删除完成检查脚本和下载文件是否实际消失。 |

本分支没有注册“删除任意媒体文件”的新能力；没有把它扩展成通用文件管理器。合并相邻批次时，如果新增删除媒体文件的能力，必须将其接入 DiskDeletion 包装和任务执行路径，不能直接暴露底层删除 Action。数据库记录删除、逻辑缓存清理、内存日志清空不会删除用户硬盘文件。截图输出复制后的临时文件清理、harness 的临时 staging 清理属于本次操作产生的内部临时资源收尾，未添加用户确认。

## 决策

1. 在 NextCore 最终 capabilities 组装时包装删除能力，底层删除 action 只保存在应用拥有的私有 executor 中。HTTP、MCP 和 Mesh 都拿到包装后的同一份能力，不能选择未包装路径。删除任务号与下载任务号分开，describe 明确输入与返回值的区别。
2. `waiting_user` 是持久任务状态，不能通过 task.resume 或 task.decide 批准。拒绝、取消、实际删除的回执进入现有 job_events / activity；未另建审批库。Next 任务界面用“等待你确认删除”“删除文件”，对话框没有标识符和执行过程说明。
3. 删除确认只适用于文件删除。快捷键冲突、性能警告、播放器选择和设备信任继续采用 Classic 的交互约束，它们不是给 destructive 添加的统一确认关卡。
4. 备份禁止键在 hydratePortableCredentials 之前过滤，避免先触及凭据保险库再判断权限。允许的注册设置复用 setter；恢复值与当前值一致时无需重复调用 setter。Classic 默认的 FullBackupService 调用不使用这些 Next 选项，原有恢复行为保留。
5. 快捷键“替换”的代码事实是 Classic 只更新目标动作，不会清空另一个相同绑定。本批保持这个行为，没有改成新的冲突解决算法。
6. Mesh 同账号身份认证不替代 Classic 被遥控授权。可信设备键为 `id:<TLS deviceId>`，沿用 Classic 临时批准、永久信任和撤销机制；Agent 仍不能修改接收开关或可信名单。

## 真实实例实验

脚本：[experiment.py](evidence/x30/experiment.py)。完整未经改写的能力响应：[operations.json](evidence/x30/operations.json)，终端记录：[experiment.log](evidence/x30/experiment.log)。运行的是本 worktree 的 `build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay`，直接 subprocess 启动，三个独立 `NIPAPLAY_PROFILE`。合成 30 秒本地视频、本地种子、弹幕、插件和备份；Mesh 使用本地 coordinator、开发 CA 和合成账号，由本地 HTTP fixture 验证。没有使用真实服务器或登录钥匙串。

实验对 Flutter 对话框的操作，是通过该实验进程的 VM service 调用实际按钮使用的 `answer(bool)` handler 来模拟用户点击；没有新增生产 API，也没有把它注册成 Agent 能力。这里证明实际对话框、等待状态、按钮执行路径和文件结果，**不是声称有真人完成了点击**。接收开关与信任撤销同样通过 Classic 原有服务配置实验状态。

### 删除等待、拒绝、执行

以下是实际 task.get 输出的字段摘录，原文见 operations.json：

```json
{"jobId":"job-12f6182c33055661761929cf8de8e585","type":"disk_deletion","state":"waiting_user"}
{"state":"failed","error":{"code":"conflict","message":"用户没有同意删除","retryable":false},"receipt":{"verification":"verified","details":{"deleted":false,"reason":"user_declined"}}}
{"state":"succeeded","receipt":{"verification":"verified","details":{"action":"plugins.delete","result":{"id":"x30.fixture","deleted":true}}}}
```

HTTP 调用插件删除，等待时脚本存在；取消后仍存在。随后 **MCP tools/call** 删除同一插件，仍先等待；选择删除后脚本不存在。下载用 librqbit 实际加载合成种子、核验已有视频：拒绝后视频和下载 session 均在，选择删除后视频不存在，删除任务 succeeded / verified。

```text
plugin file after refusal {"exists": true}
plugin file after UI Delete {"exists": false}
download file after UI Delete {"exists": false}
```

界面截图：[插件删除](evidence/x30/delete-plugin-waiting.png)、[下载删除](evidence/x30/delete-download-waiting.png)。文字为“将删除插件文件，无法恢复。要删除吗？”和“将删除下载的文件，无法恢复。要删除吗？”。截图已打开检查。

task.wait 实际返回 waiting_user；followup.register 成功，终态触发后记录 ready。临时 CODEX_HOME 未配置模型提供方，所以后续 Agent 回合没有启动，记录的原因是 `Prepare provider configuration inside the lab CODEX_HOME.`，没有借用用户的真实 Codex 配置。activity 实际包含 task.created、task.changed、task.receipt、followup.registered、followup.triggered、settings.changed、source.removed 等记录。

### 恢复备份

构造 `.npb`，尝试关闭 Agent 端点、开启遥控、改 web_server_port，同时恢复 show_system_resources。真实返回摘录：

```json
{"restoredCount":1,"skippedCount":3,"skippedItems":[{"path":"labs_enable_agent_endpoint","reason":"forbidden_setting"},{"path":"remote_control_receiver_enabled","reason":"forbidden_setting"},{"path":"web_server_port","reason":"forbidden_setting"}]}
```

Classic 实际落盘状态：

```json
{"labs_enable_agent_endpoint":true,"remote_control_receiver_enabled":false,"web_server_port":null,"show_system_resources":true}
```

恢复来源为 harness_cli，reason 为 `X30 forbidden-key experiment`，activity 有该修改。给真正导出的 `.nph` 历史记录附加 preferences 对象，再恢复，实际返回 `{"restoredCount":1}`，三个禁止设置仍保留原值。

备份内字号 100：restoredCount=0，skippedCount=1，reason=setting_rejected，字号仍 24。备份开启时间轴预览：出现同一性能警告，选择取消后 restoredCount=0，setting_rejected，预览保持 false。备份输入明文账号 token：restoredCount=0，skippedCount=1，reason=forbidden_credential_input，账号没有登录。

### 弹幕与参数

```text
danmaku.import → count=1, loaded=true
空 [] 导入 → failed / invalid_input / 弹幕文件中没有弹幕数据
danmaku.tracks → 原池 count=1
plugin danmakuLoaded observations {"before":0,"after":1}
Classic Dandanplay track after detach {"preserved":true,"bindingDetached":true}
```

解绑后的轨道 bindingId=null、count=1、loaded=true；bindingIds 仍列出持久历史绑定，未把历史记录当作当前管理绑定。单轨 offsetMs=7200001、手动偏移=45 实际成功。字号 100、非预设颜色、模糊 7、FTP 代理、Bangumi state=0 均在入口拒绝，未发出账号写请求。弹幕截图：[弹幕池](evidence/x30/danmaku-pool.png)。ui.capture 明确不包含 Erika 原生弹幕及部分原生视频覆盖层，未把截图缺少这些层解释成未加载。

GitHub 代理的本地 fixture 返回 200 时保存；第二个地址返回 503 时失败，Classic preferences 仍为第一个地址。接口中的回环 URL 被现有 redactor 隐去，所以另读该**临时 profile**的 Classic preferences 验证实际值。

时间轴预览取消后 false，同意后 true；快捷键冲突取消后仍是“空格”。截图：[性能警告](evidence/x30/timeline-warning.png)、[快捷键冲突](evidence/x30/shortcut-conflict.png)。外部播放器最初路径为空，调用启用时实际先检测到 `/opt/homebrew/bin/mpv`，路径修改与启用都有同一 invocation 的来源记录；随后关闭。没有启动 mpv。未在本机制造“无 mpv”环境来验证原生选择器取消分支，该分支有 Classic 回归测试。

临时 WebDAV 来源直接 `media.sources.remove`，无 confirm、无 --execute：实际 `removed=true, indexedFilesPreserved=true`，后续列表为空，activity 有 source.removed。

### Mesh 开关、信任与撤销

两台本 worktree 的真实实例，经本地 coordinator 完成证书注册、双向 TLS 和回环地址发布；发送端使用 `nipa mesh.invoke` 调用接收端 playback.state。

```json
{"status":"failed","error":{"code":"unavailable","message":"Classic remote control receiver is disabled.","retryable":false}}
{"status":"completed","result":{"state":{"player":"internal","status":"idle","hasVideo":false}}}
{"status":"failed","error":{"code":"conflict","message":"Classic remote control access is pending; the user must allow this device in NipaPlay.","retryable":false}}
```

三次分别对应接收开关关闭、开启且已信任、Classic 撤销可信设备。最后落盘状态 receiver=true、trusted_devices=`[]`。不是只测 Mesh 自己的认证。生产 issuer 仍为空，本实验不代表生产 Mesh 已配置完成。

### 意外与限制

- 直接运行的调试实例没有 source expression compilation service，VM evaluate 失败；改用 VM getObject / invoke 调用现有按钮 handler。该调整只在实验脚本中。
- 实验曾把脱敏后的代理接口值当作原始 URL 比较而失败；改为核对临时 Classic 持久值。保存当时输出：[proxy-redaction-observation.log](evidence/x30/proxy-redaction-observation.log)。
- 合成 Jellyfin 来源配置得到 `type 'Null' is not a subtype of type 'FutureOr<String>'`，增加 username 也未解决。本批未修改远程来源服务，改用 WebDAV 观察无确认移除。已保留失败：[source-fixture-failure.log](evidence/x30/source-fixture-failure.log)，交 B 排查。
- 第一次实际 Mesh 拒绝只有笼统的 `Remote RPC rejected the request.`，已在本批保留并传递 Classic 拒绝原因，然后重新实测三种状态：[mesh-denial-message-before.log](evidence/x30/mesh-denial-message-before.log)。
- 应用日志有原有 universal_gamepad / audioplayers MissingPluginException；本次视频、插件、下载、对话框和 Mesh 仍实际运行。没有改这些原生依赖。
- 补跑纯 Dart kernel 测试时，根工程的 Flutter 测试配置不包含 package:test，直接用 Flutter 执行该包失败。改用现有缓存的 Dart test runner 和临时 package-config 后全部通过；没有 pub get 或修改项目依赖。
- 全部三个应用 PID 已退出，三个 profile 和 coordinator 实验目录已删除；cleanup 记录均为 rootAbsent=true、processExited=true。没有启动 `/Applications/NipaPlay.app`，没有按应用名启动或寻找进程。

## 复审待确认项的判定与交接

| 审计项 | 代码事实与处理 |
|---|---|
| destructive 自填确认是否符合产品意图 | 任务书已明确规则；本批按文件删除/UI 确认，其余直接执行统一。无需再次产品确认。 |
| “清除评分” | 两个 Classic 对话框将草稿置 0，并禁用确定；详情提交只把 1–10 转成 rating payload。不是持久清零能力缺口。 |
| 降低已看 N 集 | 未建立远端撤销事实。Dandanplay 服务的 false 调用也不能当作撤销看过，本批不开放其他单集状态。 |
| 新番旧页入口 | NewSeriesPage 只有旧 HomePage 构造；现行 adaptive homeFeed 和大屏入口使用 DashboardHomePage。旧页入口不能当作现行产品入口；Dashboard 的今日新番数据仍是独立覆盖项，交 C。 |
| `/search/anime` 与 `/search/adv` | 请求路径及过滤参数不同，不能静态宣称结果集合等价。高级搜索补齐属于 C，不在 D 写另一套搜索。 |
| 继续播放自动匹配、手动重匹配、Emby 偏好继承 | 存在 Classic 专用副作用，当前公共播放路径不能据此推定全部等价；交 A/B 做状态实验。 |
| 密度图是否能通过截图读取 | ui.capture 捕获主 Flutter scene，外部/原生覆盖层有明示限制。本次没有验证密度曲线的等价读取；交 A 的观察能力实验。 |
| Bilibili/AcFun 弹幕来源 | Classic 是占位，不能计为原本已能完成的真实来源能力。 |
| 第三方插件私有登录 | 通用层只能调用插件暴露的 action；只有秘密文本项而无登录 action 的插件不能保证登录发起覆盖。具体插件仍需逐个检查，不能替用户填密码。 |
| 大于 16 MiB 本地种子 | 能确认 Next 的入口限制，不能以静态代码证明 librqbit 的实际接受上限；需专项真实输入实验，交下载负责批次。 |
| Web 客户端 | ServiceProvider 仅在 !kIsWeb 创建 NextCore。此次原生能力结论不能推广到 Web。 |
| 平台原生行为、媒体自定义字段、文件关联 | macOS 本批实际路径已观测，其他平台和逐字段映射未验证；交相邻批次，不能报全部覆盖。 |
| SMB/WebDAV 保存前验证 | service.configure 明确走 configureConnection；先保存未验证地址再登录/检查，失败无此层回滚。代码事实成立；属于 B 的配置/登录拆分路径，本批只改 capability 的 remove 小分支，不碰它的服务实现。 |

## 需要主控决定的问题

1. **无评分条目的仅短评更新是否继续允许。** Classic 编辑器要求评分>0 才能提交，Next PATCH 允许省略 rating；但 Classic Bangumi 同步也会仅更新收藏状态而不带评分。建议保留 status 的独立修改，明确是否对“无评分且只更新 comment”加约束，避免把编辑器整个草稿流程写进能力。
2. **移动端/电视隐藏的首页设置是否可以由 Agent 改。** 它们不是非法持久值，而是平台 UI 可见性不同。本批未把隐藏控件解释成安全禁止项。
3. **一个文件多个 episodeRefs 的产品语义。** Next 模型允许，Classic 精确投影只处理一个关系。应由主控协调 A/C 的身份映射契约；本批没有删减模型或声称 Classic 已接受全部关联。
4. **B 的未验证连接覆盖策略。** 已确认当前实现与 Classic 先验证后保存不同；需要 B 与主控确定暂存配置还是明确接受“配置后登录”的新语义。

删除确认的规则没有遗留产品问题；以上是审计中其余组合或模型边界。

## 验证与文件边界

- 完整 `flutter test --no-pub test/next`：**404 passed，4 skipped**。日志：[next-tests.log](evidence/x30/next-tests.log)。
- 涉及的 Classic 测试：**33 passed**。包含 backup_credentials、plugin_backup_experiment、hotkey_service_policy、external_player_settings、remote_control_settings、danmaku_track_timing、danmaku_style、plugin_danmaku_buffering。日志：[classic-tests.log](evidence/x30/classic-tests.log)。
- `packages/nipa_harness/test` 纯 Dart 内核回归：**88 passed**。使用 Flutter 3.44.6 所带 Dart、现有 test 1.31.0 / test_core 0.6.17 缓存和 `/tmp/nipa-next/x30-kernel-package-config.json`；日志：[kernel-tests.log](evidence/x30/kernel-tests.log)。
- 关键新增文件与最终修改的备份、Mesh 路径 analyze：**No issues found**。日志：[analyze.log](evidence/x30/analyze.log)。
- 本 worktree 的 debug macOS 构建成功；Flutter 3.44.6、--no-pub、ERIKA_PREBUILT_CACHE_DIR。日志：[build.log](evidence/x30/build.log)。
- 自动化只守审批状态、拒绝不写入、凭据边界与 Classic 默认行为等约束。功能结论来自上述真实运行输出。

共同文件的小改动：NextCore 仅加 executor 与包装；agent_endpoint 仅移除预览关卡；danmaku capability 仅范围与说明；media_sources capability 仅 remove；application_settings / classic_settings / registry 为范围、Classic 交互及 describe；ui_data/service 仅任务自然标题；plugin_service 新可选 allowScriptRemoval 默认 true；full_backup_service 新可选恢复适配与默认关闭的限制；video_player_state_danmaku 的改动位于 Next 使用的 installSource / removeSource 桥接。没有改 Classic 普通加载、删除与恢复入口的默认行为。

没有新增或修改依赖，工作分支没有 commit / push。构建自动变动的 Podfile.lock 恢复为 HEAD。未修改其他批次的服务实现；合并时应保留各方在这些共同文件中的独立片段。
