# 自动化与个人工具

## 个人 harness

个人 harness 是梨花工作所在的 Git 仓库，用户可以直接编辑。默认位于用户目录下的 `nipaplay-harness`（macOS、Linux 为 `~/nipaplay-harness`，Windows 为 `%USERPROFILE%\nipaplay-harness`），位置在「设置」→「梨花」→「文件夹」→「梨花的文件夹」中查看和修改。

| 路径 | 内容 |
|---|---|
| `AGENTS.md` | 梨花每次工作读取的指令：角色、原则、能力入口。可追加个人要求 |
| `memory/` | 记忆。`MEMORY.md` 为索引，`preferences.md` 等为具体内容，对应「梨花记得的事」 |
| `tools/` | 可复用脚本，如 Mikan 资源搜索、弹幕获取、公开 HTTP 请求。梨花在工作中补充 |
| `hooks/` | 事件程序与定时程序 |
| `nipa` | 命令行客户端，调用 NipaPlay 的全部能力 |

Next 每次启动时，将应用自带的官方种子（`AGENTS.md`、`tools/`、`hooks/README.md` 等）以 Git 合并方式并入 harness，保留个人提交、记忆和工具。存在冲突或未提交的修改时，harness 保持原状，结果记录在 `./nipa status` 的 `harnessSeed.autoUpdate` 中；处理后重启 Next 重新合并。

## `nipa` 命令行

梨花调用的工具对应 NipaPlay 注册的 Action，如 `media.search`、`download.add`、`playback.open`。在 harness 目录中运行（Windows 用 `python nipa`）：

```sh
./nipa status                              # 连接与宿主状态
./nipa list                                # 当前注册的全部 Action
./nipa describe download                   # 能力族说明与动作列表
./nipa describe download.add               # 单个 Action 的参数、副作用与结果说明
./nipa call app.capabilities '{}'          # 本设备当前的能力
./nipa call task.list '{}'                 # 后台任务
./nipa query VIEW '{"limit":20}'           # 读取状态视图，字段用 state.describe 查询
./nipa watch TASK_ID --seconds 40          # 等待任务结束
./nipa --device 工作站 list                 # 查询组网中的另一台设备
```

- 参数以 `describe` 的实时结果为准，随版本和设备变化。
- 每个 Action 标注为只读、写入或破坏性操作；可否撤回、是否幂等见各自的 `describe`。
- 结果较大时，终端显示概要，完整的脱敏结果写入 `records/`，输出中给出路径。
- 完整目录见 [Action 参考](../development/ACTION_REFERENCE.md)。

## 事件程序

`hooks/` 下以事件名命名的可执行程序在事件发生时运行：

| 事件 | 触发时机 |
|---|---|
| `download.completed` | 下载任务完成并校验入库 |
| `download.file_completed` | 单个文件下载完成、校验通过并登记入库 |
| `download.stalled` | 下载连续五分钟没有新数据（含无法获取元数据） |
| `library.file_added` | 文件首次进入媒体索引 |
| `playback.started` | 一段播放首次进入播放状态 |

- 标准输入为 JSON：`{"event","objectId","occurredAt","data"}`；工作目录为 harness 根目录。
- 程序中可调用 `nipa`，连接凭据由环境变量 `NIPAPLAY_ENDPOINT_FILE` 指向的文件提供。
- 每次运行是一个 `harness.hook` 任务，回执记录退出码、耗时、是否超时，以及脱敏后的标准输出与错误输出末尾。最长 60 秒，退出码 0 为成功。查看：`./nipa call task.list '{"type":"harness.hook"}'`。
- 同一事件与对象的程序未结束时不重复运行。`download.file_completed` 和 `download.stalled` 为持久事件，同一对象只运行一次，重启后不重跑。
- 关闭 Next 终止运行中的程序；被中断的程序在重启后不重跑。
- macOS、Linux 的程序需可执行权限和 shebang；Windows 按扩展名运行 `.exe`、`.cmd`、`.bat`、`.py`。

`./nipa query harness.hooks '{}'` 列出各事件对应程序的状态（缺少执行权限的程序被忽略）和最近一次运行结果。完整说明见 harness 中的 `hooks/README.md`。

## 定时程序

`hooks/schedules.json` 为数组，每项声明一个定时程序：

```json
[
  {"id": "check-updates", "program": "hooks/check", "everySeconds": 900},
  {"id": "nightly", "program": "hooks/daily", "dailyAt": "19:30"}
]
```

- `everySeconds`（正整数）与 `dailyAt`（本机时区 `HH:mm`）二选一。文件每秒读取一次，修改即时生效。任一项无效时，整个文件的定时程序都不运行。
- 标准输入中 `event` 为 `schedule`，`objectId` 为该项的 `id`。
- 最长运行 15 分钟；同一项上次未结束时，跳过本次。
- 仅在 NipaPlay 运行且 Next 开启时执行，错过的次数不补跑。
- `./nipa query harness.schedules '{}'` 列出各项是否有效及原因、程序是否可执行、下次运行时间、最近一次运行和跳过次数。

## 唤醒梨花

巡查由脚本执行，需要判断时唤醒梨花：

```sh
python3 nipa call agent.wake '{"instruction":"字幕组的 RSS 有更新，看看要不要下载", "facts":{"item":"…"}}'
python3 nipa call activity.report '{"title":"检测到变化", "source":"我的巡查脚本", "facts":{}}'
```

- `agent.wake` 默认在主对话开始新一轮，`threadId` 可指定其他对话。进行中的回合不被打断，唤醒排队等待。
- `activity.report` 记录一条发现，不唤醒梨花。

此类自动化可直接交给梨花建立：

> 每天晚上检查在追的番有没有更新，有就下载并告诉我。

梨花编写巡查脚本并配置 `schedules.json`，脚本和配置保存在 harness 中，可随时查看和修改。

## 后续

梨花可以登记后续（`followup.register`）：指定事件发生后回到原对话继续工作，如某个文件下载完成（`download.file_completed`）、某个下载停滞（`download.stalled`）。后续与唤醒共用持久队列，重启后保留。查看和取消：`followup.list`、`followup.cancel`。

脚本发起的下载没有所属对话，停滞通知通过 `download.stalled` 事件程序或后续获得。

## SQL

Next 的数据保存在 SQLite 数据库 `next.db` 中。领域工具之外，梨花可以直接查询和修改：

| 动作 | 作用 |
|---|---|
| `db.describe` | 每张表的列、主键、外键、含义、可写性及原因，以及跨表规则 |
| `db.query` | 执行一条 `SELECT`（含 `WITH … SELECT`）。连接为只读；结果受行数和字节上限约束，截断时给出续读位置；凭据值被遮蔽 |
| `db.write` | 一批 `INSERT`、`UPDATE`、`DELETE`（最多 100 条，同一事务）。不带 `previewId` 时预演并回滚，返回各表增删改的行及前后值；带 `previewId` 时提交预演的效果 |
| `db.receipt` | 按原 `previewId` 查询提交回执 |
| `db.undo` | 恢复某次提交前的内容，要求相关行仍为该次提交后的状态；`dryRun:true` 只预览 |

- 可写的表为媒体身份与资料、弹幕绑定、书架和展示；任务、后续、会话、历史、缓存为只读，由 SQLite 触发器强制。
- 预演后相关行发生变化时，提交被拒绝，需重新预演。
- 直接写入不同步到 Classic，不产生领域工具的回执。
- 凭据不在此数据库中。

通过组网，`db.*` 可作用于其他设备的数据库（`./nipa --device 名字 call db.query …`），属于加入组网时给予的信任，见[加入意味着什么](../use/devices.md#加入意味着什么)。在其他设备上运行程序（`program.run`）需该设备开启「允许别的设备在这里运行程序」。

批量修改前按[数据与恢复](data-and-recovery.md)备份。

---

上一篇：[请求示例](../use/examples.md) · 下一篇：[DSH 高级配置](dsh-config.md)
