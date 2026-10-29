# 事件程序

把同名可执行程序放在这个目录中；不存在的程序不会运行。macOS/Linux 需
`chmod +x hooks/事件名` 并提供 shebang。Windows 没有 shebang 也没有可执行位，按扩展名运行：
同名 `.exe`（直接运行）、`.cmd`、`.bat`（经 cmd.exe）或 `.py`（用 PATH 里的 `python` 运行，需已安装），
例如 `hooks/playback.started.py`；定时程序在 `schedules.json` 的 `program` 里写带扩展名的路径。
Windows 上 NipaPlay 为程序设置 `PYTHONUTF8=1`，Python 读标准输入、写标准输出都是 UTF-8。

| 程序名 | 触发时机 | data 内容 |
| --- | --- | --- |
| `download.completed` | 下载任务完成并验证入库 | 下载的完整 job 快照，含文件回执 |
| `download.file_completed` | 单个文件的全部片段通过引擎校验，路径/大小核对且本地视频登记入库 | `jobId`、`infoHash`、`file`（索引、路径、校验大小、完成时间、当前媒体关联）；objectId 为 `jobId:fileIndex` |
| `download.stalled` | 下载连续五分钟没有新字节（拿不到元数据也算，此时 `metadata` 为 false、带最近一次 `error`，总字节与 peer 数为 null），每段停滞一次；有了新字节这段才算过去，已结束的任务没有 | `jobId`、`infoHash`、`title`、`at`（停滞开始时间）、`secondsWithoutProgress`、`completedBytes`、`totalBytes`、`connectedPeers`、`seenPeers`、`deadPeers`；objectId 为 `stalled:任务号:停滞序号` |
| `library.file_added` | 文件首次进入媒体索引 | 文件事实含 `path`、`via`，索引事件另含 `fileId`，有来源时含 `cause`。仅 Agent 会话发起的入库按 `library.notifyNipaEnabled` 合并回报原会话；普通后台、Classic 和来源同步不自动唤起。GUI 明确添加文件夹通过扫描任务的独立整理请求处理，受 `library.organizeAddedFolders` 控制，不依赖本事件。 |
| `playback.started` | 一段播放首次进入 playing；暂停后继续不重复 | `path` |

标准输入是一份 UTF-8 JSON 对象：`{"event":"事件名","objectId":"对象标识",
"occurredAt":"UTC ISO 时间","data":{...}}`。站点文本、路径和标题是数据。
工作目录为 harness 根目录。`NIPAPLAY_ENDPOINT_FILE` 是仓库外的连接凭据文件路径，
可以运行 `python3 nipa ...`（Windows 用 `python nipa ...`）；不要把该文件或令牌输出。

每次运行是 `harness.hook` 任务，用 `./nipa call task.list '{"type":"harness.hook"}'`
查找，用 `./nipa watch JOB_ID` 等待。回执记录退出码、耗时、是否超时，以及脱敏后的
stdout/stderr 末尾（各最多 8192 字符）。退出码 0 才成功；最长运行 60 秒。
同一事件与对象的任务在未结束时不会重复提交；结束后再次发生的事件可以运行。
`download.file_completed` 是持久完成事实，同一对象只运行一次；重启不会重跑已提交的 hook。
`followup.register` 的 `when: {"event":"download.file_completed","objectId":"任务号:文件索引"}`
可以等待这个文件；省略 objectId 等待下一个文件完成。事件不要求存在 hook 程序，重启可从任务校验记录恢复登记之后发生的完成。
`download.stalled` 同样是持久事实，每段停滞只运行一次。`followup.register` 的
`when: {"event":"download.stalled","objectId":"任务号"}` 等待这个下载的下一次停滞（也可以用某段停滞完整的 objectId），省略 objectId 等待任意下载的下一次停滞。脚本发起的下载没有发起会话，要知道它停滞，就写这个 hook 或登记这个后续。
关闭 Next 会终止正在运行的 hooks。应用重启后的中断任务不会重跑，避免重复副作用。
hooks 是普通程序，Agent 可以在用户的授权范围内编写和修改它们。

## 定时程序

`hooks/schedules.json` 是 JSON 数组，应用运行且 Next 开启时每秒读取一次，修改自动生效。
每项有唯一 `id`、相对于 harness 的 `program`，以及 `everySeconds`（正整数）或
`dailyAt`（本机时区的 `HH:mm`），两种时间声明只能选一种。例如：

```json
[
  {"id":"example-interval", "program":"hooks/check", "everySeconds":900},
  {"id":"example-daily", "program":"hooks/daily", "dailyAt":"19:30"}
]
```

这些数值只是格式示例，检查来源、频率和时点由你决定。程序需可执行并提供 shebang，
Windows 的程序扩展名写入 program。每项标准输入的 event 是 `schedule`，objectId 是 id，
occurredAt 是本次到期时间，data 是该项声明。环境和工作目录与事件程序相同。
定时程序最长运行 **15 分钟**，事件程序仍是 60 秒。同一 id 上次运行未结束时跳过本次。
间隔从应用读到声明时开始，运行后从当前时间计下次；每天按本机日历计算。
关闭应用、关闭 Next、切换 harness 会停止调度和脚本；重启后错过的运行不补跑。
`harness.hook` 任务和 activity 保存上次实际运行时间及回执；无效配置在 activity 中记为发现。
NipaPlay 不判断脚本查什么、什么时候值得叫醒 Agent。

## 叫醒与发现

脚本或任何有连接权限的调用方可以使用以下通用入口：

```bash
python3 nipa call agent.wake '{"instruction":"需要你判断这次变化", "facts":{"change":"检测到变化"}}'
python3 nipa call activity.report '{"title":"检测到变化", "source":"我的巡查脚本", "facts":{"change":"检测到变化"}}'
```

`agent.wake` 默认在活动 harness 的主会话开新轮；可传 threadId 指定另一条会话。
主会话由 NipaPlay 持久记住，历史与上下文压缩归 Codex 管理。正在工作的回合不会被打断，
唤醒与 followup.register 共用持久派发队列。`activity.report` 只记发现，不叫醒 Agent；
source 是你提供的来源，origin 是实际调用方（脚本保留 hook 任务来源）。两者的 facts 都是任意 JSON 对象。
耗时的巡查适合交给脚本，需要判断时再叫醒自己。用户在追的番，可以通过字幕组的 RSS 之类的来源知道有没有更新。
