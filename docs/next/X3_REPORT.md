# X3：用户拥有的 harness

2026-10-11，主仓库 `next/capability-layer`。

## 1. 完成了什么

- 开启 Next 时从 `assets/next/harness/` 创建默认 `~/nipaplay-harness`。种子有 `AGENTS.md`、`nipa`、无令牌的 `.codex/config.toml`、`.gitignore` 和 `hooks/README.md`。有 git 时初始化并提交一次；没有 git 时保留种子文件。已存在的目录、空目录或符号链接都不写入。删除了容器工作区生成代码与旧 `assets/next/AGENTS.md`，不迁移旧工作区。
- 实验室显示仓库路径，可修改、打开；路径同样通过 `settings.*` 的 `next.harnessPath` 暴露，保存 GUI/Agent 来源。切换活动仓库会重启端点并轮换令牌。
- 连接文件在 macOS/Linux 的 `~/.config/nipaplay/endpoint.json`，Windows 的 `%APPDATA%\NipaPlay\endpoint.json`。Unix 权限为 0600；Windows 设置仅当前用户的文件 ACL。先限制临时文件权限，再写入并替换；路径含符号链接时也检查凭据是否落在 harness 内。
- `nipa` 仅用 Python 标准库，支持 `status/list/describe/call/query/watch`、JSON 或 `@文件`、`--execute` 和 `--device`。Windows 用 `python nipa`。输出 UTF-8 JSON，凭据字段、已知令牌及 URL 脱敏；回环连接直接访问，不经过 `HTTP_PROXY`。
- 新增同端口 `/harness` JSON 入口，与 `/mcp` 共用 Bearer、Host、Origin 检查和 Harness。CLI 调用来源为 `harness_cli`；MCP 保留。
- hooks 接入下载成功回执、媒体索引提交后的新增文件、Classic 媒体库新增路径、播放器首次进入 playing。程序从 stdin 取得 JSON，cwd 为 harness，`NIPAPLAY_ENDPOINT_FILE` 指向外置连接文件。每次运行进入现有 SQLite 任务与事件表，回执包含退出码、耗时、超时标记和脱敏 stdout/stderr 末尾。
- 删除覆盖率基线、兼容映射、固定九项能力测试和旧工作区覆盖测试；保留身份、任务、回执、迁移、设置及 Classic 约束测试。

没有新增依赖、主仓库提交、push、pub get，也未改动原有 `macos/Podfile.lock` 修改。初始提交只发生在新建的实验 harness 仓库中。没有读取用户 download-harness 的任何凭据文件。

## 2. 决策

1. **让种子成为普通仓库代码。** 应用只在路径不存在时复制；既有仓库不升级、不补文件、不重写 Codex 配置。种子创建先在同级临时目录完成，再发布目录。初始提交使用本次命令的本地作者配置，禁用签名和 git 模板/提交 hooks，不修改用户 git 配置。
2. **CLI 使用直接 JSON，MCP 继续服务其他客户端。** `call` 的破坏性预览在端点检查 schema 后返回，不调用 Action，也不创建执行任务。`describe/list` 返回当前契约。Mesh 使用现有 `mesh.devices` 的认证目录及 `mesh.invoke` / `mesh.invoke_destructive`，按完整设备名或 ID 唯一匹配；离线缓存不当作实时目录。
3. **等待属于任务基础设施。** `watch` 组合 `task.get` 与 `task.wait`，总等待窗口为 0–60 秒；遇到终态、暂停或需要决定即返回。没有 CLI 后台守护进程。
4. **事件基于已经发生的事实。** 下载完成采用任务成功回执，不采用进度 100%；文件事件在数据库事务提交后发出，回滚不发事件。启用时已有库和已有播放会话作为基线，不补跑历史事件；同一播放暂停后继续不重复触发。
5. **hooks 复用任务引擎。** 同一事件/对象的非终态任务共用一个任务 ID，事件键使用摘要，避免含秘密的对象地址进入去重键。启停代次防止旧队列在新一轮 Next 中误执行。中断恢复返回明确的失败回执，不自动重跑有副作用的程序。
6. **hooks 的执行和输出等待都有截止时间。** 默认 60 秒，终止收尾最多再等 1 秒；输出各保留 8192 字符。先对完整行脱敏再截取，超大未结束行省略，避免截断后留下秘密片段。时间限制针对直接启动的程序和回执等待；主动脱离父进程的后台子程序由 hook 自己管理。
7. **Codex 配置沿用 X1 实测项。** `danger-full-access`、`never`、`web_search = "live"`；完整权限已允许联网。配置不登记静态 MCP 令牌，能力发现交给 `nipa list`。只修改种子 AGENTS 的 nipa 用法说明。

## 3. 实验

### 从种子运行真实 CLI、端点、任务和 hook

复现：

```sh
~/development/flutter-3.44.6/bin/dart --packages=.dart_tool/package_config.json scripts/next/x3_experiment.dart
```

脚本只在系统临时目录操作。它调用生产 `AgentEndpoint`、仓库创建器、`TaskEngine`、`SqliteJobStore`、`HarnessHooks` 和种子 `./nipa`；端点监听真实回环 TCP 的随机端口。领域任务采用两个合成 Actions：写入实际 24 字节文件的 `experiment.write` 和删除它的 `experiment.delete`，不访问真实下载站点或用户媒体。脚本把 CLI 的 PATH 指向系统 Python，实际解释器为 macOS 自带 3.9.6。

真实输出：

```text
Seed repository: initial commits=1, nipa mode=493
Credential mode=384; outside repository=true
CLI interpreter: Python 3.9.6
```

493 和 384 分别为 0755、0600 的十进制值。

`status` 完整输出：

```json
{
  "status": "running",
  "version": "x3-experiment",
  "repository": "/var/folders/7t/363d2swj60v08tg0lbxg9gnc0000gn/T/nipa-x3-Ta3cCj/harness",
  "actions": 6,
  "tasks": {
    "status": "completed",
    "result": {"jobs": []}
  }
}
```

`./nipa list` 实际返回 6 项完整 schema。下面是其中一项的原始输出，其余 ID 为 `experiment.write`、`task.cancel`、`task.get`、`task.list`、`task.wait`：

```json
{
  "id": "experiment.delete",
  "title": "delete fixture file",
  "description": "Delete the delivered experiment file.",
  "effect": "destructive",
  "inputSchema": {"type": "object", "properties": {}, "additionalProperties": false},
  "outputSchema": {"type": "object", "properties": {}, "additionalProperties": true}
}
```

写入调用使用 `@input.json`。以下是输出摘录，字段和值保留原样：

```text
$ ./nipa call experiment.write @/var/folders/7t/363d2swj60v08tg0lbxg9gnc0000gn/T/nipa-x3-Ta3cCj/input.json
"status": "completed"
"jobId": "job-56e7c139f6512b256cfed1a825c606ff"
"state": "queued"
"origin": "harness_cli"

$ ./nipa watch job-56e7c139f6512b256cfed1a825c606ff --seconds 5
"state": "succeeded"
"verification": "verified"
"path": "/var/folders/7t/363d2swj60v08tg0lbxg9gnc0000gn/T/nipa-x3-Ta3cCj/delivered.txt"
"size": 24
```

破坏性预览的完整输出：

```text
$ ./nipa call experiment.delete {}
{
  "status": "preview",
  "action": "experiment.delete",
  "effect": "destructive",
  "input": {},
  "executed": false,
  "description": "Delete the delivered experiment file.",
  "violations": []
}
```

下载任务的成功变更经生产 `taskChanged` 事件处理触发 `hooks/download.completed`，不是手工启动 hook。程序校验 stdin、cwd 和凭据文件环境变量，把收到的事件保存到 `records/hook-event.json`。再用 CLI 等待 hook 任务；回执原始部分如下：

```text
$ ./nipa watch job-70a5c66c887868f3d36d32797be2f867 --seconds 5
"event": "download.completed"
"objectId": "job-56e7c139f6512b256cfed1a825c606ff"
"jobId": "job-70a5c66c887868f3d36d32797be2f867"
"type": "harness.hook"
"state": "succeeded"
```

```json
{
  "verification": "verified",
  "details": {
    "exitCode": 0,
    "elapsedMs": 376,
    "timedOut": false,
    "stdoutTail": "{\"event\": \"download.completed\", \"received\": true}\n",
    "stderrTail": "cookie=[redacted]\n"
  }
}
```

脚本随后修改 harness 的 AGENTS，记录包括 `.git`、hook、运行记录在内全部条目的摘要、权限和 mtime，再关闭并重开端点，逐项比较。真实输出：

```text
Event observed by executable: {"event":"download.completed","objectId":"job-56e7c139f6512b256cfed1a825c606ff","received":true}
Existing harness: 45 entries; bytes, modes, and mtimes unchanged=true
Destructive preview: delivered file still exists=true
EXPERIMENT COMPLETE
```

另以仅包含 chmod 的临时 PATH 启动生产创建器，使系统找不到 git。实际输出：

```text
No git: seed files=5, git metadata=false
```

Flutter 测试生成的资产包也包含全部 5 个种子文件，包括隐藏的 `.codex/config.toml` 和 `.gitignore`。

### Codex 种子配置复验

```sh
python3 -u scripts/next/verify_codex_workspace.py
```

脚本改为从完整种子创建临时仓库；使用独立临时 Codex home 和合成模型端点。实际输出：

```text
codex-cli 0.144.1
seed config: no token or MCP connection
sandbox_mode: "danger-full-access" (origin: project)
approval_policy: "never" (origin: project)
web_search: "live" (origin: project)
thread: {"approvalPolicy": "never", "sandbox": {"type": "dangerFullAccess"}}
live web_search tool: present
command execution: {"exitCode": 0, "aggregatedOutput": "outside workspace\nnetwork available\n", "status": "completed"}
turn status: completed; approval requests: 0
```

### 数据约束与回归检查

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub test/next test/security
# 00:25 +365: All tests passed!

# 在 packages/nipa_harness 中
~/development/flutter-3.44.6/bin/flutter test --no-pub
# 00:00 +87: All tests passed!
```

新增约束检查包括：空目录/符号链接不改写、重开时文件内容和 mtime 保留、旧令牌在两种入口被拒绝、凭据目录隔离、8 个相同事件共享一个任务、回执中没有合成秘密、超时和退出码 3 都不产生 verified 成功、中断 hook 不重跑。最后一次修改后针对端点、hooks、仓库、媒体原语和身份重跑：`00:02 +29: All tests passed!`。

变更文件 analyze：`No issues found! (ran in 2.6s)`；包中变更的 endpoint/engine analyze：`No issues found! (ran in 0.1s)`。包全量 analyze 另有原来 `mcp/rpc.dart` 的两条花括号 info，未改无关文件。`git diff --check` 通过。

观察到的失败与修正：

- 最初 `HarnessLocation` 在构造时读取 SharedPreferences，使未启用 Labs 的纯 Core 测试提前访问 Flutter binding。改为按需加载，365 项回归通过。
- 最初把包测试从主仓库一起运行，主包的 package config 找不到包自己的 `package:test`。改为在 `packages/nipa_harness` 下运行，未运行 pub get，87 项通过。
- 文件事件的第一版在每次索引调用后重新扫描整个位置表。改为事务内收集新增位置、提交后只发送新增项；既有记录和失败事务不发事件。

范围：这是非沙箱宿主的回环实验，不是 macOS 沙箱内真机下载/播放实验。当前 macOS App Sandbox 的权限问题仍由 `next/desandbox` 处理；本实现按非沙箱 HOME 和外部程序执行环境工作。Windows 的 CLI、路径、ACL 和 hook 启动分支已实现，未在 Windows 真机运行。CLI 的 Mesh 路由使用现有 Mesh 接口；365 项中包含真实 mTLS Mesh 约束测试，本次没有另做跨设备 `nipa` 真机实验。

## 4. 问题

需要主控决定的问题：没有。

交付摘要：用户拥有的 harness、仓库外轮换凭据、标准库 nipa 和三个 hooks 已完成；选择直接 JSON 调用与现有任务回执，既有仓库完全不写入。Python 3.9.6 的真实回环实验、hook 回执、仓库保留、Codex 权限复验及数据约束测试通过。主控可在去沙箱整合后做真机任务观察。
