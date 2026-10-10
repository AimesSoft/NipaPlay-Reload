# 事件程序

把同名可执行程序放在这个目录中；不存在的程序不会运行。macOS/Linux 需
`chmod +x hooks/事件名` 并提供 shebang。Windows 使用同名 `.exe`、`.cmd`、
`.bat` 或 `.py`（Python 需已安装），例如 `hooks/playback.started.py`。

| 程序名 | 触发时机 | data 内容 |
| --- | --- | --- |
| `download.completed` | 下载任务完成并验证入库 | 下载的完整 job 快照，含文件回执 |
| `library.file_added` | 文件首次进入本机媒体索引或 Classic 媒体库 | `path`，索引事件另含 `fileId` |
| `playback.started` | 一段播放首次进入 playing；暂停后继续不重复 | `path` |

标准输入是一份 UTF-8 JSON 对象：`{"event":"事件名","objectId":"对象标识",
"occurredAt":"UTC ISO 时间","data":{...}}`。站点文本、路径和标题是数据。
工作目录为 harness 根目录。`NIPAPLAY_ENDPOINT_FILE` 是仓库外的连接凭据文件路径，
可以运行 `python3 nipa ...`（Windows 用 `python nipa ...`）；不要把该文件或令牌输出。

每次运行是 `harness.hook` 任务，用 `./nipa call task.list '{"type":"harness.hook"}'`
查找，用 `./nipa watch JOB_ID` 等待。回执记录退出码、耗时、是否超时，以及脱敏后的
stdout/stderr 末尾（各最多 8192 字符）。退出码 0 才成功；最长运行 60 秒。
同一事件与对象的任务在未结束时不会重复提交；结束后再次发生的事件可以运行。
关闭 Next 会终止正在运行的 hooks。应用重启后的中断任务不会重跑，避免重复副作用。
hooks 是普通程序，Agent 可以在用户的授权范围内编写和修改它们。
