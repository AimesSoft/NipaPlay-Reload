# X33：回合工作过程、Next 详情入口与真实开头弹幕

2026-10-12，Asia/Taipei。worktree `~/Desktop/nipaplay-next-wt/x33-replay`，分支 `next/x33-replay`。已读 TEAM、X31、Y3、Y2、X32，并参照 X23 的实验环境。未 commit、push、pub get 或改用户 Codex 配置；没有访问登录钥匙串或真实数据目录，没有启动安装版，也没有操作 ui-demo。所有实例直接运行本 worktree 的 Debug 可执行文件，独立临时 profile，默认安静；没有激活窗口、像素点击或按应用名寻找进程。

## 1. 完成了什么

- 新增 `chat.turn.process {threadId, turnId}`，返回 `{found, process}`。记录实际来源、回合状态与起止时间；按执行顺序保存命令文本、状态、退出码、耗时、脱敏输出，以及宿主实际收到的思考摘要。独立落盘，重启可读；模型宿主未就绪时也能从当前 harness 的文件读取。没有记录原始思考正文。
- `ChatHost.readThread` 用这份事实补充 Codex 历史，保留用户和助手消息，替换 Codex 聚合后的过程项。Y3 现有 `ChatHostPort.readThread → TurnActivity.fromHistory` 接入点即可重建侧栏步骤，没有改侧栏。
- `ui.open` 接受 `workId`，也继续接受作品的 `entityId`。Next 可见时调用已有 `NextShellController.openWork`，返回 `interface: next`；不可见时走原 Classic 作品详情，返回 `classic`。直接 animeId、其他 Classic 页面/窗口和文件/剧集播放入口保持原语义。
- 主视觉弹幕取消短语白名单。从目录第一集开头取真实原文，不足六句才扩到第二、第三集的开头。新增设置 schema `next.heroOpeningSeconds`，默认 180 秒，范围 30–300 秒，Agent 可用 settings.get/set，GUI 可用同一 schema。

接口与保留策略见 [chat/README](../../lib/next/chat/README.md)，弹幕与路由契约见 [ui_data/README](../../lib/next/ui_data/README.md)。

## 2. 决策

**工作过程由宿主记录，不从调用 journal 猜。** journal 只有 nipa 能力调用，不能代表 Python、shell 等所有执行；回合边界能标时间，却补不出命令正文和退出状态。宿主直接记录 Codex 的 turn/item started/completed，在秘密检查和脱敏之后写文件。输出仅采用 completed item 的聚合输出，避免把跨 delta 分割的秘密片段写盘。

每个绝对 harness 路径对应 Next 数据目录 `turn-process/` 下一个文件；不写 Agent 的仓库，也不复制完整对话。原子替换，最多保留最近 60 回合、4 MiB，超过上限先删最早回合。单轮最多 128 项；命令最多 4096 个 Unicode 字符、输出 8192，摘要最多八段、每段 2048。截断记录 `truncated`。保留 started 事实，因此异常中止的命令可以有未知退出状态；没有收到 completed 时不编造退出码、最终耗时或输出。旧版从未保存的过程和已淘汰记录返回 found=false。

**界面连接只暴露打开作品。** `WorkDetailBridge` 是一个可挂载/卸载的回调，返回 null 表示 Next 当前不可见、false 表示 Next 详情未能打开。异步取作品前后都检查外壳的实际可见状态，避免请求期间退出 Next 后仍宣称打开了 Next。能力层不持有 Navigator 或界面模型；Classic 不需要读取 Next 设置来改变自己的路径。

唯一修改的 `lib/next/ui/` 文件是 `shell/next_shell.dart`：挂载回调、检查可见状态、调用已有 openWork，dispose 时卸载，共十行连接。没有改 Y5 正在做的界面文案、布局、侧栏或详情页。

**弹幕按开头时间取样，不判断剧情。** 使用现有有效绑定和缓存，沿用文件范围、偏移及多集文件约束，不增加后台网络请求。先第一集，再必要的第二、第三集；每集只读前述时间窗，并受已有时长和范围裁剪。文本 2–18 个 Unicode 字符，合并空白；排除网址/域名/IP、控制字符、四个以上连续重复字符，以及重复三次以上的短字符组。去掉标点和空白、转小写后跨剧集去重。按剧集和时间排序，同刻按文本排序，最多六句。没有剧情关键词或反应短语白名单，也没有把真实观众文字改写成套话。

设置保存在 SQLite 的现有 ui_cache 命名项，不升级数据库、不改已有记录；settings 来源与修改历史沿用注册表。开头时间限制只能缩小剧透机会，不能保证观众没有提到后续剧情；短剧不足三分钟时会覆盖整集。

## 3. 实验与真实输出

主驱动为 [x33_experiment.py](../../scripts/next/x33_experiment.py)，回环 Responses 模型为 [x33_provider.py](../../scripts/next/x33_provider.py)。模型名称为 `deepseek-v4.1-flash`；这是无凭据假模型，不声称访问了真实 DeepSeek。它发出工具请求，命令实际由嵌入的 Codex app-server 执行。临时配置含独立 CODEX_HOME、公共 CA 副本、NO_PROXY，不借用用户 auth/config。

完整能力返回：[operations.json](evidence/x33/operations.json)，真实宿主事件：[chat.jsonl](evidence/x33/chat.jsonl)。

### 两个会话、三轮命令，退出后重启

最终观察用了主会话两轮、新会话一轮，以同时验证按会话隔离。实际 App PID 为 68225，退出后从同一临时 profile 启动 PID 68597，恢复同一个主会话。随后三次 `chat.turn.process` 都返回 found=true。

第二轮真实返回摘录（字段原样）：

```json
{
  "threadId":"01a12cd6-c7c3-7a80-aa93-39580db41471",
  "turnId":"01a12cd6-ce55-7ab2-88d5-57caaad60556",
  "status":"completed",
  "durationMs":398,
  "command":"/bin/zsh -c \"python3 -c 'import time; time.sleep(0.35); print(\\\"退出状态已收到\\\"); raise SystemExit(7)'\"",
  "exitCode":7,
  "commandStatus":"failed",
  "commandDurationMs":325,
  "aggregatedOutput":"退出状态已收到\n"
}
```

上面 commandStatus/commandDurationMs 对应实际 items 中的 status/durationMs，为区分回合和命令改了摘录键名。原响应包含两段摘要：“先执行这条命令，再看看结果。”“结果已经收到。”

另外两轮实际命令退出码为 0，协议报告命令耗时均为 0ms；回合耗时分别为 65ms、44ms，不把小于毫秒精度的命令补成更长耗时。第一轮输出实际为：

```text
开头检查完成
cookie=[redacted]
```

第三轮 Authorization 的输出已被现有脱敏器变为 CredentialRef 占位。其重复脱敏会把占位文字进一步改写成多层 `CredentialRef(diagnostic, secret)`；完整原返回保留在 operations.json，没有改造成较好看的输出。三份过程均断言不存在合成的 `synthetic-private-value`。

读历史时发现 Codex 其实保存了一项**合并后的摘要**，它的 ID 与实时两个摘要 ID 不同；只按相同 ID 合并会出现三项思考。修正为已保留过程替换历史过程类别，保留消息类别。只对这个改动重放已有真实事件，没有重跑三轮模型实验：[x33_history_replay.dart](../../scripts/next/x33_history_replay.dart)、[history-replay.jsonl](evidence/x33/history-replay.jsonl)。最终输出三轮均为：

```json
{"commands":1,"summaries":2,"messagesPreserved":true}
```

这最后一步是原事件的离线回放；此前的实际实例重启和三次接口查询已经完成，不把回放当成另一次 App 重启。

### Next 开和关，ui.open 与截图

实验作品为“长安十二时辰”，Classic 身份 33001 和本地文件是明确制造的隔离 fixture，不是线上匹配结果；文件是文本占位，没有启动播放器。两个状态实际返回：

```json
{"opened":true,"interface":"next","actual":{"kind":"work_detail","workId":"work-e4fb5663cad1c6cfceea0af04c98fcf321e244e14a5c568226da962c38dfd27e","interface":"next"}}
{"opened":true,"interface":"classic","actual":{"kind":"work_detail","animeId":33001,"entityId":"work-e4fb5663cad1c6cfceea0af04c98fcf321e244e14a5c568226da962c38dfd27e"}}
```

分别调用 `ui.capture`，返回同一 PID 68597、实验 profile 和本 worktree executablePath。已逐张目视检查：[Next 详情](evidence/x33/next-detail.jpg) 是深色大标题、Next 顶栏与剧集卡；[Classic 详情](evidence/x33/classic-detail.jpg) 是 Classic 首页上的详情窗口。没有用返回值代替截图观察。

### 有明确来源的第一集真实弹幕缓存

起初现有弹弹play网关 search 返回 authenticationRequired：[首次失败](evidence/x33/initial-gateway-failure/experiment.log)。没有绕过网关、放松账号约束或使用用户登录。

随后读到旧临时集成实验的“长安十二时辰 S01E01.xml”，16197 条，开头 1057 条，投影挑出了打卡文字。这份文件原始获取来源无法核实，因此它只用于缓存规模与接口观察，不作为“真实观众来源”的证据。其原记录标签 existing-real-cache 是当时的判断，最终结论不依赖这个标签。创建 Classic fixture 时还遇到了 runtime 已创建 watch_history 表的冲突；改实验准备为 IF NOT EXISTS，失败和清理记录保留在 [initial-history-fixture-failure](evidence/x33/initial-history-fixture-failure/experiment.log)。

最终只补做来源和弹幕投影，不重跑对话、详情开关或截图：[x33_public_cache.py](../../scripts/next/x33_public_cache.py)、[完整返回](evidence/x33/public-cache/operations.json)。公开目录接口确认《雪宝带你看电影》第一集“雪宝带你看《小美人鱼》”，CID 1034761585、BV1WA411y7yS；公开 comment XML 取得 161 条，缓存 SHA-256 为 `0273e385f9ddf86ac529d7f948c13c9adc0853ba0788c98068443520ccd1ef7e`。[原缓存](evidence/x33/public-cache/episode-1.xml) 保留供核对。

来源：`https://api.bilibili.com/pgc/view/web/season?season_id=44813` 与 `https://comment.bilibili.com/1034761585.xml`。这是实验输入的公开文件获取，再用应用已有 danmaku.import/Classic 解析器保存缓存；没有在 Next 代码新增 Bilibili 客户端。绑定的本地作品/文件仍是隔离 fixture，未把制造的 Classic 身份 33002 宣称为官方身份。PID 68890 的真实实例返回：

```json
{"title":"雪宝带你看电影","danmaku":["恭喜你挖到宝藏","恭喜宝藏发现我！！！","感谢宝藏发现了我","看我发现了什么好东西","看我发现了什么！","这是什么！"]}
```

这六句分别逐条匹配公开缓存原文，时间为 0、0.094、0.316、1.313、1.959、3.347 秒，均在第一集开头，没有人工挑出好看的句子替换算法输出。这是一部不足三分钟的短剧，不能把结果推广为长番剧的内容多样性或无剧透证明。

设置时间窗的真实返回也已观察到：

```json
{"key":"next.heroOpeningSeconds","value":120,"revision":1,"scope":"user","apply":"immediate"}
```

### 检查与清理

- Flutter 3.44.6，全部 --no-pub。缺失 package_graph 和 Swift `.packages` 等派生输入时，只读复制相同 pubspec.lock 的 x32 worktree 派生文件并重定位到本 worktree；没有解析依赖或在那里构建。Erika 预编译缺失时用指定 `ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache`。最终包含历史合并修正和完整网址过滤的构建见 [build-delivery-urls.log](evidence/x33/build-delivery-urls.log)。CocoaPods 自动修改的 Podfile.lock 已恢复。
- 所有 Flutter 测试经 lockf 队列、清除代理。迭代约束 5 项通过：[constraints.log](evidence/x33/constraints.log)。完整 test/next **只运行一次，433 项通过、4 项跳过**：[full-next.log](evidence/x33/full-next.log)。之后历史合并新约束第一次暴露 Dart 泛型 List.addAll 的类型错误，改为构造替换列表；仅重跑该文件，两项通过：[history-constraints-fixed.log](evidence/x33/history-constraints-fixed.log)。没有重跑全量。
- 最终相关模块 analyze 无 error/warning，保留 11 项花括号风格和实验脚本 print 的 info：[analyze-final.log](evidence/x33/analyze-final.log)。git diff --check 通过。
- 所有实验 App PID 55505、67890、68225、68597、68890 都已按 PID 退出并复查；对应 profile 均不存在，公共输入暂存目录也已删除：[cleanup.json](evidence/x33/cleanup.json)。回环模型服务随驱动结束，临时配置/CA/数据库随 profile 删除。保留的证据没有端点凭据。原 audioplayers/gamepad MissingPluginException 和未登录远程服务日志未隐藏，也未在本任务改插件。

## 4. 还缺什么与问题

旧版未记录的过程无法补回；异常中止、尚未完成命令的最终输出没有记录。思考摘要只保存模型实际提供的内容，不能保证每个模型都有摘要。当前新接口和历史接入已完成，未另做侧栏逐步展开截图，也未验证超过保留上限的大规模真实会话；持久化、隔离、脱敏和淘汰由约束测试守住。

真实来源的弹幕验证使用短剧第一集；长番剧开头以及扩到第二、第三集的真实缓存观察尚未做。未声称文本规则能排除所有剧透，也未声称已经观察首页漂浮动画。

需要主控决定的问题：**没有**。
