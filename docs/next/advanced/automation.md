# 自动化与个人工具

这一篇面向想让梨花"自己盯着"做事，或者想直接动手写脚本的用户。读之前最好已经熟悉[和梨花对话](../use/nipa.md)。

## 个人 harness

每个人有一个属于自己的 Git 仓库，叫个人 harness。梨花在这里工作，你也可以直接编辑它。默认位置是用户目录下的 `nipaplay-harness`（macOS/Linux 的 `~/nipaplay-harness`，Windows 的 `%USERPROFILE%\nipaplay-harness`），可以在「设置」→「梨花」→「文件夹」→「梨花的文件夹」里查看和修改。

| 路径 | 内容 |
|---|---|
| `AGENTS.md` | 梨花每次工作都会读的指令：她的角色、做事原则、常用入口。你可以追加自己的要求 |
| `memory/` | 她的记忆：`MEMORY.md` 是索引，`preferences.md` 等是具体内容。也就是「梨花记得的事」 |
| `tools/` | 可复用的脚本，例如资源站搜索（Mikan）、弹幕、公开 HTTP 请求。她会补充新工具 |
| `hooks/` | 事件程序和定时程序，见下文 |
| `nipa` | 命令行客户端，所有应用能力都从这里调用 |

Next 每次启动时，会把应用自带的官方种子（`AGENTS.md`、`tools/`、`hooks/README.md` 等）以 Git 合并的方式并入你的 harness。你的提交、记忆和工具会保留；有冲突或未提交的修改挡住合并时，保持原状，不覆盖、不 stash。结果在 `./nipa status` 的 `harnessSeed.autoUpdate` 里，解决后重启 Next 会再试一次。

## `nipa` 命令行

梨花调用的"工具"，本质上是 NipaPlay 注册的一个个 Action（例如 `media.search`、`download.add`、`playback.open`）。在 harness 目录里可以直接用命令行调用（Windows 用 `python nipa`）：

```sh
./nipa status                              # 连接与宿主状态
./nipa list                                # 当前注册的全部 Action
./nipa describe download.add               # 某个 Action 的说明、参数、副作用和结果怎么判读
./nipa call app.capabilities '{}'          # 这台设备当前能做什么
./nipa call task.list '{}'                 # 后台任务
./nipa query VIEW '{"limit":20}'           # 读一个状态视图，字段用 state.describe 查
./nipa watch TASK_ID --seconds 40          # 等待一个任务结束
./nipa --device 工作站 list                 # 查询组网里另一台设备
```

- 参数以 `describe` 的实时结果为准，不同版本、不同设备可能不同。`describe <族>`（例如 `describe download`）给出整族说明和动作列表。
- 结果太大时，终端只显示概要，完整的脱敏结果写在 `records/` 下，输出里会给出路径。
- 每个 Action 都标明自己是只读、写入还是破坏性操作。但这个分类不等于可撤回或幂等，具体看 `describe` 里的说明。
- 完整目录见 [Action 参考](../development/ACTION_REFERENCE.md)。

## 事件程序

把可执行程序放在 `hooks/` 下，以事件名命名，事件发生时就会运行：

| 事件 | 触发时机 |
|---|---|
| `download.completed` | 下载任务完成并校验入库 |
| `download.file_completed` | 单个文件下载完成、校验通过并登记入库 |
| `download.stalled` | 下载连续五分钟没有新数据（包括拿不到元数据） |
| `library.file_added` | 文件首次进入媒体索引 |
| `playback.started` | 一段播放第一次进入播放状态 |

- 程序从标准输入读取一份 JSON：`{"event","objectId","occurredAt","data"}`，工作目录是 harness 根目录。
- 程序里可以调用 `nipa`。连接凭据通过环境变量 `NIPAPLAY_ENDPOINT_FILE` 指向的文件提供，不要输出这个文件。
- 每次运行都是一个 `harness.hook` 任务，回执记录退出码、耗时、是否超时，以及脱敏后的标准输出和错误输出末尾。最长 60 秒，退出码 0 才算成功。用 `./nipa call task.list '{"type":"harness.hook"}'` 查看。
- 同一事件和对象的程序还没结束时，不会重复运行。`download.file_completed` 和 `download.stalled` 是持久事件，同一对象只运行一次，重启也不重跑。
- 关闭 Next 会终止正在运行的程序；重启后，被中断的不再重跑，避免重复副作用。
- macOS/Linux 的程序需要 `chmod +x` 并带 shebang；Windows 按扩展名运行 `.exe`、`.cmd`、`.bat`、`.py`。

`./nipa query harness.hooks '{}'` 列出每个事件对应的程序是否就绪（没有执行位的会被忽略）和最近一次运行的结果。完整说明见 harness 里的 `hooks/README.md`。

## 定时程序

`hooks/schedules.json` 是一个数组，每项声明一个定时运行的程序：

```json
[
  {"id": "check-updates", "program": "hooks/check", "everySeconds": 900},
  {"id": "nightly", "program": "hooks/daily", "dailyAt": "19:30"}
]
```

- `everySeconds`（正整数）和 `dailyAt`（本机时区的 `HH:mm`）二选一。应用每秒读取一次这个文件，修改后自动生效。**任何一项无效，整个文件里的定时程序都不运行。**
- `./nipa query harness.schedules '{}'` 列出每一项是否有效及原因、程序是否可执行、下次到点时间、最近一次运行，以及因上次没结束而跳过的次数。
- 程序收到的标准输入里，`event` 是 `schedule`，`objectId` 是这一项的 `id`。
- 定时程序最长运行 15 分钟；同一项上次没结束时，跳过本次。
- **只在 NipaPlay 运行且 Next 开启时执行**。关机、退出应用、切回 Classic 期间不运行，重启后也不补跑错过的次数。

## 让脚本叫醒梨花

耗时的巡查适合交给脚本，需要判断时再叫醒梨花：

```sh
python3 nipa call agent.wake '{"instruction":"字幕组的 RSS 有更新，看看要不要下载", "facts":{"item":"…"}}'
python3 nipa call activity.report '{"title":"检测到变化", "source":"我的巡查脚本", "facts":{}}'
```

- `agent.wake` 默认在主会话开一轮新对话，也可以传 `threadId` 指定另一条对话。正在进行的回合不会被打断，唤醒会排队等它结束。
- `activity.report` 只记录一条发现，不叫醒她。

最简单的方式是直接告诉梨花你的需求，例如「每天晚上检查我在追的番有没有更新，有就下载并告诉我」。她会自己写脚本、配置定时程序。写完后检查一下脚本和 `schedules.json` 再让它长期运行。

## 后续（followup）

除了脚本，梨花也可以登记"后续"（`followup.register`）：等某个事件发生后回到原对话继续工作，例如"这个下载完成或卡住时告诉我"。等待的事件可以是 `download.file_completed`（某个文件或下一个文件完成）、`download.stalled`（某个下载或任意下载停滞）等。

后续和唤醒共用一个持久队列，应用重启后仍然有效。查看和取消用 `followup.list`、`followup.cancel`，或者直接问她"现在登记了哪些后续"。

由脚本发起的下载没有所属对话。要知道它卡住了，就写 `download.stalled` 事件程序，或者登记一个后续。

## 数据库查询与修改（SQL）

Next 的数据保存在 SQLite 数据库 `next.db` 里，梨花可以直接查询，做领域工具覆盖不到的整理：

| 动作 | 作用 |
|---|---|
| `db.describe` | 列出每张表的列、主键、外键、含义，可不可写及原因，以及跨表规则 |
| `db.query` | 执行一条 `SELECT`（含 `WITH … SELECT`）。连接本身是只读的；结果有行数和字节上限，被截断时给出续读位置；值里的凭据被遮蔽 |
| `db.write` | 一批 `INSERT`/`UPDATE`/`DELETE`（最多 100 条，同一事务）。不带 `previewId` 时只预演并回滚，返回每张表增删改的行和前后值；带上 `previewId` 才提交预演过的效果 |
| `db.receipt` | 用原 `previewId` 查询提交回执。响应丢失时先查回执，不要换个 key 重做 |
| `db.undo` | 恢复某次提交之前的内容。只有相关行仍等于那次提交后的样子才会执行；`dryRun:true` 只看不改 |

边界：

- 只有 `db.describe` 标为可写的表能改：媒体身份与资料、弹幕绑定、书架和展示。任务、后续、会话、历史、缓存是只读的，由 SQLite 触发器强制。
- 预演之后这些行又被改过，提交会被拒绝，重新预演即可。
- 直接写入不会同步到 Classic，也不产生专用工具的领域回执。能用专用工具（`media.*`、`danmaku.*`）完成的，优先用专用工具。
- 凭据不在这个数据库里。

SQL 也可以通过组网作用于另一台设备的数据库（`./nipa --device 名字 call db.query …`），这属于加入组网时给出的信任，见[加入意味着什么](../use/devices.md#加入意味着什么)。在别的设备上运行程序（`program.run`）则需要那台设备另外开启「允许别的设备在这里运行程序」。

批量修改前先[备份](data-and-recovery.md)，并让她先把预演结果给你看。

---

上一篇：[可以让梨花做什么](../use/examples.md) · **➡️ 下一篇：[DSH 高级配置](dsh-config.md)**
