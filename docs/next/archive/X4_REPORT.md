# X4：第一次见面的输出、状态查询与种子更新

2026-10-11。主仓库分支 `next/capability-layer`；基线 `f5a08af5862a45e62f665462e5b686edc0e0e1fe`。

## 1. 完成了什么

- 种子 `nipa list` 默认只返回全部能力的 `id/effect/title`；`status` 返回应用信息、任务总数、各状态数量、未结束任务总数与最多 10 个未结束任务的简要信息。`--full` 保留完整输出；`describe ACTION` 直接请求单项契约，不再下载整个目录。
- 修复 `state.query` 对非有限数值的公开投影，取消阻碍真实读取的默认耗时、并发、扫描与输出限制。查询仍只读、字段白名单闭合、秘密不可见、URL 去认证信息、本地位置遵守授权。
- 应用在 Next 数据目录下的 `harness-seed` 维护种子 git 历史：种子内容或可执行权限发生变化才提交；新 harness 从它克隆，远端 `nipaplay`、分支 `main`，具有共同祖先。现有 harness 的文件和 git 配置都不写入。
- 种子 AGENTS 的命令示例、概况与详情用法、更新远端事实和辅助脚本提交要求已更新。
- 可重复的规模实验留在 `scripts/next/x4_experiment.dart`；回归测试覆盖投影、查询不写数据、种子版本共同祖先、内容删除、新增和现有仓库保留。

没有改动媒体身份与 Classic 库的关系；没有改动 `next/one-library` worktree。没有提交或推送主仓库，没有运行 pub get，没有改动 `macos/Podfile.lock` 的已有修改。没有退出或重启真实 NipaPlay，没有写入用户的 `~/nipaplay-harness`。

## 2. 决策

### 概况先行，详情显式获取

默认保留 JSON，便于脚本组合。能力目录不分页，60 项能力索引只需约 6 KB；schema 与完整说明留给 `describe`。任务历史不进入默认 status；失败任务数量仍可见，具体回执用 `task.list` 筛选、`task.get` 获取。未结束任务展示上限为 10，并同时给出 `activeTotal`，避免把截取误认为全集。

端点收到 `full:false` 时在服务端投影，减少传输与解析。未传 `full` 的旧种子客户端继续收到原来的完整格式；新 CLI 也会自行投影旧端点的完整结果，因此 Agent 可以先更新 CLI。Mesh 设备使用同样的概况字段，在客户端投影其目录和任务。

### `state_read_failed` 的真实原因

只读检查现有 Classic 历史：215 条记录中有 **1 条 `watch_progress=Infinity`，对应 `duration=0`**。没有输出或修改记录内容。把 Next 数据库和历史复制到隔离临时目录，使用生产 `library.files` 供应器复现：来源读取和公开对象投影成功，`limit=100` 成功；`limit=200` 在 `StateCapability.query` 原第 261 行的输出字节预算计算中抛出：

```text
source rows=267
query limit=100 rows=100 warnings=[]
query exception=JsonUnsupportedObjectError
StateCapability.query (package:nipaplay/next/state/query.dart:261:23)
Converting object to an encodable object failed: Infinity
```

外层把它归一成了 `state_read_failed`。当前隔离副本是 267 行，实验 1 当时是 367 行；未把两次观测当作同一快照。规模实验另用 367 行合成记录，把同样的 Infinity 放到排序后的第 138 行，旧代码再次复现相同的 100/200 行分界。

非有限数值在公开投影边界转换为 `null`，含义为未知；Infinity、负 Infinity、NaN 都不能写入 JSON。这不会把未知观看进度说成完成，也不修改 Classic 历史或存储值。修复后隔离副本的 100/200 行查询都成功，规模实验也确认来源仍保留 Infinity。

### 去掉没有实测保护对象的预算

删除两条活动来源读取的并发上限、默认/最大 1000 ms 期限、5000 行扫描窗口、总计 200 行输出限制、256 KiB 输出预算、数组 200 项限制、关联两级限制，以及过滤 `in` 的 200 值限制。状态视图中的绑定和任务文件数组也不再静默截取。

根页和每个关联默认仍为 50 行，`limit` 接受正整数，Agent 用 `select/limit/cursor` 决定输出量。完整来源扫描之后再排序，默认不再出现“只排序扫描窗口”的语义。保留调用者显式选择的 `timeoutMs`，无预设最大值；只有主动指定时才可能报告 `time_limit`。保留输入 64 KiB 上限、合法查询校验、查询绑定 cursor、声明关系、秘密白名单与只读约束。

旧期限超时后，底层异步读取继续占着并发名额，源码中没有取消它；后续请求因两个名额被占用而收到 `query_concurrency_limit`。现在默认等到来源完成，显式超时也不会封锁其他读取。

### 种子是应用的仓库，harness 是用户的仓库

每次启动 Next 端点先维护本地种子仓库，再仅为不存在的 harness 克隆它。用 `main` 作为稳定分支名；克隆使用 `--origin nipaplay --no-local`，保留共同历史且不共享本地 git 对象的硬链接。提交使用应用自己的身份，禁用提交签名与提交 hook，不依赖用户的 git 身份设置。

只有内容或 git 记录的可执行位变化才新增提交，应用版本号变化本身不提交。新增和删除的种子文件都进入同一版本。初始空种子也能产生可克隆的根提交；没有 git 时沿用直接交付种子文件的行为。

种子目录与用户 harness 必须分离，包括符号链接解析后的包含关系。应用不为旧 harness 自动添加 remote；旧 harness 的 Agent 若要接入，可自行添加指向本地 `next/harness-seed` 的 `nipaplay` 远端，并判断已有独立历史如何整合。新 harness 已有 remote 和共同祖先，普通 fetch/merge 即可。

## 3. 实验

使用 Flutter 3.44.6，无 pub get，所有 Flutter test/analyze 命令都带 `--no-pub`。HTTP 客户端与 Python CLI 都直连回环地址。实验不使用正在运行的真实应用端点。

```bash
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  scripts/next/x4_experiment.dart --reporter expanded

~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next test/security --reporter expanded

~/development/flutter-3.44.6/bin/flutter analyze --no-pub \
  lib/next/agent_endpoint.dart lib/next/harness_repository.dart \
  lib/next/next_runtime.dart lib/next/state scripts/next/x4_experiment.dart \
  test/next/agent_endpoint_test.dart test/next/harness_repository_test.dart \
  test/next/state_query_test.dart
```

实验脚本固定原始基线提交，可用 `NIPAPLAY_X4_BASE` 指定其他旧版本。文件记录、任务、连接凭据、应用数据库、种子历史和用户仓库全部在临时目录，结束时删除。使用真实 NextCore、SQLite、生产 `library.files` 供应器、真实 `/harness` HTTP 端点与种子 CLI；外部下载和 Classic 写入端口使用离线 fixture。367 个唯一文件中 107 个是实际创建的本地文件，其余为远程位置；71 个任务含完整回执，50 成功、17 失败、2 运行、2 暂停。

### 默认输出大小

在同一个测试端点上分别运行基线 CLI、新 CLI、新 CLI `--full`，计数为 stdout 的 UTF-8 字节，包含末尾换行；新 `--full` 与旧默认的 JSON 完全一致。

```text
baseline query limit=100: rows=100
baseline query limit=200: {"status":"failed","error":{"code":"internal","message":"state_read_failed","retryable":false}}

Fixture: files=367, tasks=71; production Core, SQLite, /harness, HTTP_PROXY bypass
list: before=343765 B, after=6355 B, full=343765 B, reduction=98.15%
list sample (60 actions): [{"id":"credentials.status","effect":"read","title":"凭据保险库状态"},{"id":"danmaku.align","effect":"write","title":"danmaku.align"},{"id":"danmaku.align_apply","effect":"write","title":"danmaku.align_apply"},{"id":"danmaku.align_keep","effect":"write","title":"danmaku.align_keep"}]
status: before=126402 B, after=1357 B, full=126402 B, reduction=98.93%
```

实验 1 的历史观测是 list 361,906 B、status 107,208 B；本次离线目录含 60 个真实 Core/库能力，任务是同规模合成记录，所以两次完整输出大小不同。上面新旧对比使用相同数据与相同端点。

本次真实 `./nipa status` 输出：

```json
{
  "status": "running",
  "version": "x4-experiment",
  "repository": "/var/folders/7t/363d2swj60v08tg0lbxg9gnc0000gn/T/nipa-x4-W4p64f/harness",
  "actions": 60,
  "tasks": {
    "total": 71,
    "byState": {
      "succeeded": 50,
      "failed": 17,
      "running": 2,
      "paused": 2
    },
    "activeTotal": 4,
    "active": [
      {
        "jobId": "fixture-67",
        "title": "Episode 67 download",
        "state": "running",
        "phase": "download",
        "progress": {"completed": 10, "total": 20, "unit": "bytes"}
      },
      {
        "jobId": "fixture-68",
        "title": "Episode 68 download",
        "state": "running",
        "phase": "download",
        "progress": {"completed": 10, "total": 20, "unit": "bytes"}
      },
      {
        "jobId": "fixture-69",
        "title": "Episode 69 download",
        "state": "paused",
        "phase": "download",
        "progress": {"completed": 10, "total": 20, "unit": "bytes"}
      },
      {
        "jobId": "fixture-70",
        "title": "Episode 70 download",
        "state": "paused",
        "phase": "download",
        "progress": {"completed": 10, "total": 20, "unit": "bytes"}
      }
    ]
  }
}
```

### 连续完整翻页与慢来源

每页 50 行，沿真实端点返回的 cursor 翻到结尾；5 轮顺序后再同时进行 4 轮。逐轮验证总行数、唯一 ID 数、warnings；脚本没有重试逻辑。

```text
CLI query limit=500: rows=367, warnings=[], nonfinite progress=null; source remains Infinity
sweep 1: pages=8, rows=367, unique=367, failures=0, retries=0, elapsed=698 ms
sweep 2: pages=8, rows=367, unique=367, failures=0, retries=0, elapsed=645 ms
sweep 3: pages=8, rows=367, unique=367, failures=0, retries=0, elapsed=639 ms
sweep 4: pages=8, rows=367, unique=367, failures=0, retries=0, elapsed=628 ms
sweep 5: pages=8, rows=367, unique=367, failures=0, retries=0, elapsed=643 ms
sweep 6: pages=8, rows=367, unique=367, failures=0, retries=0, elapsed=2326 ms
sweep 7: pages=8, rows=367, unique=367, failures=0, retries=0, elapsed=2332 ms
sweep 8: pages=8, rows=367, unique=367, failures=0, retries=0, elapsed=2336 ms
sweep 9: pages=8, rows=367, unique=367, failures=0, retries=0, elapsed=2342 ms
slow default query: rows=1, warnings=[], elapsed=1204 ms (> former 1000 ms budget)
```

合计 72 页、3,303 次文件行观察，零失败、零重试。另一个来源主动延迟 1200 ms，默认查询仍完整返回；显式 timeout 的语义和三个同时超时请求不会互相封锁，也有约束测试。

### 种子升级

创建 harness 后原样维护一次种子，HEAD 不变。Agent 写入自己的笔记后，保存整个 harness（含 `.git`）的文件指纹、权限和 mtime。模拟升级新增 `seed-upgrade.txt`，停启的只是测试端点。应用处理升级后完整指纹一致，再由实验中的 Agent 命令执行 fetch 和 merge。

```text
$ git remote -v
nipaplay /var/folders/7t/363d2swj60v08tg0lbxg9gnc0000gn/T/nipa-x4-W4p64f/seed (fetch)
nipaplay /var/folders/7t/363d2swj60v08tg0lbxg9gnc0000gn/T/nipa-x4-W4p64f/seed (push)

Upgrade application start: harness bytes, modes and mtimes unchanged=true
$ git fetch nipaplay
From /var/folders/7t/363d2swj60v08tg0lbxg9gnc0000gn/T/nipa-x4-W4p64f/seed
   e71b3a9..18a0dd9  main       -> nipaplay/main

seed commits=2 (unchanged seed created no commit)
$ git show nipaplay/main:seed-upgrade.txt
version 2

$ git merge --ff-only nipaplay/main
Updating e71b3a9..18a0dd9
Fast-forward
 seed-upgrade.txt | 1 +
 1 file changed, 1 insertion(+)
 create mode 100644 seed-upgrade.txt

Agent merge: upgrade file present=true, local notes retained=true; EXPERIMENT COMPLETE
00:08 +1: All tests passed!
```

fetch 后、Agent 合并前，工作区仍没有升级文件。约束测试另外验证种子中修改文件、删除旧文件、新增文件，并验证 Agent 自己改过的 harness 文件仍原样保留；fetch 后 `merge-base HEAD nipaplay/main` 是最初的种子提交。

### 回归与意外

```text
flutter test --no-pub test/next test/security --reporter expanded
00:24 +369: All tests passed!

flutter analyze --no-pub [上述变更范围]
No issues found!
```

实验过程中的失败已处理：第一版 fixture 把 JobProgress 写成 const 导致编译失败，改用实际构造器；Flutter 测试绑定把直接 HttpClient 请求替换成 HTTP 400，实验显式关闭 HTTP mock 并设置 DIRECT；第一轮完整并发读虽成功，但合成 download 任务缺少真实下载后端信息，触发了无关的周期刷新异常，任务类型改为 fixture 后完整实验通过。没有为这些实验问题修改应用下载逻辑。

原始成功日志在 `/tmp/nipa-next/x4-experiment.log`、`x4-tests.log`、`x4-analyze.log`。临时真实数据副本和诊断测试已清理；可复用的实验脚本保留在仓库。没有重跑首次对话的模型实验，因此不声称测得整次会话 token 降幅。运行中的应用未加载本次改动；本次验收范围是 macOS 离线端点与回归，Windows 未做真机实验。

## 4. 问题

需要主控决定的问题：没有。
