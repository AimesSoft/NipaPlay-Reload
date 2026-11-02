# X8：Classic 投影的可核验撤销

日期：2026-10-11。主仓库：`~/Desktop/NipaPlay-Reload`，分支：`next/capability-layer`。

## 1. 完成了什么

修复 Agent 文件绑定经 Next 投影到 Classic 后不能完整撤销的问题。新投影在 Classic SQLite 写事务中保存原行 ID、四个匹配字段的前像和后像；撤销仅在原行仍存在、行 ID 和匹配字段仍等于投影后像时恢复前像。只改标题、重匹配、删除行、删除后重建相同匹配，都保留 Classic 并返回可见冲突。观看进度、观看时间、位置、缩略图、media_key、扫描标记等不参与恢复写入。

`media.identity.unbind_batch` 的失败消息明确区分 **Next bindings revoked** 与 **Classic not restored**。成功文件条目包含 `classicProjectionId` 及逐路径 `classicProjection` 结果（`status`、`restored`）；成功回执持久保存，重启和原 requestId 重试保持该操作的原确认结果。`media.identity.get.conflicts` 继续暴露失败 outbox。独立 Classic 同集匹配返回 `unchanged / restored=false`；新版投影从未写入 Classic 时返回 `not_written / restored=false`。

修复空标题投影：从同一外部对象的非空 provider 快照取标题，跳过空值和 Classic 观察快照；没有可用 provider 标题时保留 Classic 对应非空字段，再无证据则拒绝投影，不写空字符串。原值在投影日志中保存，撤销恢复它，而不是调用 Classic 的清除匹配逻辑。

端点概况和现有种子 `nipa status` 现在返回 `harnessSeed`：种子绝对路径、main commit、远端位置、是否指向此种子、已抓取 commit、是否落后及状态。端点只读 git 信息，不 fetch、不合并、不改用户文件。现有新版 `nipa` 会直接显示端点新增字段，不需要改 CLI 逻辑。

真实 NipaPlay 没有退出或重启。没有读写用户 `~/nipaplay-harness`、`~/Documents/nipaplay` 下的数据；所有写入实验均在系统临时目录。没有 commit、push、pub get 或依赖修改；git 实验在临时夹具仓库中创建历史，主仓库没有提交。进入任务时已有的 `macos/Podfile.lock` 修改保留原样。

## 2. 决策

### 把撤销证据放在实际发生写入的数据库

新增 Classic 表 `next_classic_projection_journal`，以 `(projection_id, file_path)` 为主键，保存 `before_fields`、`after_fields`、`row_existed`、`row_id`、`state`。CREATE TABLE IF NOT EXISTS 与写历史、写日志在同一 Classic 事务内执行。这样不会出现“Classic 已写、Next 尚未保存前像”的跨库窗口。Next 仍使用原 outbox，不另建投影队列；投递后回读才完成。

Classic `user_version=2`、`watch_history` 表结构及 Next `schema=8` 不变。日志首次投递时才创建，启动的只读同步不修改 Classic。日志及原 outbox 均保留，不清理或回算旧数据。失败插入日志会回滚同事务的 Classic 字段更新；已有日志和历史不受影响。撤销的原始来源审计仍保存在 Next `media_evidence`。

原本不存在的历史行撤销后保留历史行：匹配 ID 恢复为 null，集标题恢复 null，作品名使用原路径文件名。删除整行可能丢掉投影之后用户产生的观看进度，故只撤销匹配。已有行则逐值恢复原有四列，包括 null、旧的保留 ID 和原文件名。

### 比较字段，而不是猜测操作者

比较原行 ID 和全部四列：`anime_id`、`episode_id`、`anime_name`、`episode_title`。ID 相同但标题改过也不能覆盖；行删除后重建也不能当成原行。进度变化允许撤销，恢复写入不会覆盖进度。

Classic 原本已有相同匹配时只登记 `unchanged`，不重写标题，撤销也不恢复或清除这条独立事实。不能因同步生成了 `classic_match` 绑定就跳过撤销检查；实际是否由 Next 写入，以原子日志为依据。

同一文件增删另一来源身份会触发同集再次投影。这种确认通过 `previousProjectionId` 继承前一仍由 Next 写下的匹配的原始前像，不能把它误记为独立 Classic 匹配。原行已被修改时，只保存继承的撤销证据、返回 conflict，不改 Classic；最后撤销仍显示 conflict，不会被一次失败的再次投影遮掉。

新版 outbox 的 `journalVersion=1` 表明它只会经带原子日志的写入器投递。该版本没有日志意味着没有提交 Classic 写入，撤销可报告 `not_written`。旧版无此标记且无日志，不能作同样推断，返回 conflict 并保留 Classic。旧的 pending clear 也不会再直接清空真实历史。

成功回执保存该操作对应的 projection ID 和 Classic 确认结果。后续重新绑定之后重试旧撤销请求，仍返回旧撤销回执，不会撤销新绑定或改报新绑定的投影结果。

### 标题必须有证据

旧 `_queueFileProjection` 直接取最新快照的 `title`，没有非空检查；旧 Classic 写入器又直接覆盖 `anime_name`。因此代码确实允许把已有文件名写成空字符串。夹具覆盖上游作品名为空以及较新集标题为空的情况。此次没有复原已被主控恢复的本机现场，也不据此断言当时具体是哪份快照返回了空标题。

现有非空 provider 快照是同一外部对象的证据；缺少时当前 Classic 非空原值也是保留依据。两者均没有时返回冲突，不编造作品名或集名。原值即使被非空 provider 标题替换，也完整保存在撤销前像中。

### status 的落后含义

`trackingBehindSeed` 比较 harness 已抓取的 `refs/remotes/nipaplay/main` 与应用维护种子的当前 main。它不依赖先 fetch 才发现更新。`current` 只表示远端跟踪引用最新，不表示用户 HEAD 已合并。

状态区分 `missing_remote`、`not_fetched`、`different_remote`、`behind`、`current`、`diverged`、`unrelated_or_unknown`、`seed_unversioned`、`git_unavailable`。无法确定时落后字段为 null，不报 false。不同远端不会被当成此种子的更新状态；不联系网络远端。

### 历史空标题是否需要修复

**若受影响构建已经分发，已有损坏值得修复，但不能做“所有空 anime_name 自动补齐”的迁移。** Classic 的清除匹配本来就可能留下空标题和旧 ID；批量补齐会把用户主动清除的记录重新变成匹配。

旧 outbox、`media_classic_observations`、`media_legacy_history`、来源快照或用户备份可以用于列出疑似候选和原值证据，但旧 outbox 没有原子前像，也没有足够信息排除后续 Classic 编辑。观察到旧 ID 相同不等于有权恢复原标题。本次保留这些记录，不从它们自动生成撤销日志或修改历史。

建议在确认受影响版本分发范围后，提供候选预览，逐项确认来源及原值，再作有比较条件和备份的修复。可靠备份可恢复原值；只有 provider 非空标题证据时，最多能提出标题修复，不能声称恢复了投影前的整行。本机已由主控恢复，无需再次修复。本次历史兼容夹具验证无日志时明确返回 conflict，Classic 保持原值。

## 3. 实验

### 真实 SQLite 夹具

`test/next/projection_undo_experiment_test.dart` 使用生产 `WatchHistoryDatabase` schema、`WatchHistoryMetadataPort`、Next SQLite、MediaRuntime、Harness Action、TaskEngine；元数据是离线弹弹play fixture，视频是临时合成文件。初始 Classic 行有 null 匹配 ID、非空文件名、非零进度、media_key、时间及缩略图。不是内存端口模拟恢复。

最终相关范围命令：

```sh
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/projection_undo_experiment_test.dart \
  test/next/one_library_experiment_test.dart \
  test/next/media_classic_projection_test.dart \
  test/next/media_identity_test.dart \
  test/next/harness_repository_test.dart \
  test/next/agent_endpoint_test.dart --reporter expanded
```

实际输出（抽取各轮 X8 验证行及最终相关范围结束行）：

```text
X8 bind: {"anime_id":7001,"episode_id":7101,"anime_name":"动画样本","episode_title":"第一话"}
X8 undo: {"anime_id":null,"episode_id":null,"anime_name":"original-filename.mkv","episode_title":null}; restored=true; wholeRowEqual=true; retry/restart=true
X8 reentry: second bind/undo restored=true; foreign_key_check=[]
X8 title conflict: code=conflict; NextRevoked=true; ClassicUnchanged=true; identityConflict=true; retry=conflict; message=Entry 0: Next bindings revoked; Classic projection is in conflict: Classic not restored: matching fields changed or the row was deleted after projection; Classic was left untouched.
X8 ids conflict: code=conflict; NextRevoked=true; ClassicUnchanged=true; identityConflict=true; retry=conflict; message=Entry 0: Next bindings revoked; Classic projection is in conflict: Classic not restored: matching fields changed or the row was deleted after projection; Classic was left untouched.
X8 delete conflict: code=conflict; NextRevoked=true; ClassicUnchanged=true; identityConflict=true; retry=conflict; message=Entry 0: Next bindings revoked; Classic projection is in conflict: Classic not restored: matching fields changed or the row was deleted after projection; Classic was left untouched.
X8 recreate conflict: code=conflict; NextRevoked=true; ClassicUnchanged=true; identityConflict=true; retry=conflict; message=Entry 0: Next bindings revoked; Classic projection is in conflict: Classic not restored: matching fields changed or the row was deleted after projection; Classic was left untouched.
X8 progress: restored matching=true; last_position=900000; watch_progress=0.9; other columns unchanged=true
X8 repeated projection: secondary source bind/unbind kept Classic match=true; final undo restored original row=true
X8 repeated projection after Classic title edit: secondary bind=conflict; final undo=conflict; Classic untouched=true
X8 repeated projection after Classic ids edit: secondary bind=conflict; final undo=conflict; Classic untouched=true
X8 journal interruption: Classic write rolled back=true; prior evidence retained=true; same-request retry restored=true
X8 new row undo: IDs=null; anime_name=new-file.mkv; retained history/progress=true
X8 empty upstream anime title: projected anime_name=original-filename.mkv; restored=true
X8 empty newer episode title: retained earlier provider title=第一话; original row restored=true
X8 interrupted undo: readback=unavailable; Classic already restored=true; restart outbox=delivered; receipt.restored=true; row unchanged=true
X8 legacy projection: conflict=no atomic undo evidence; Classic untouched=true
X8 missing title evidence: bind=conflict; Classic unchanged=true; undo.status=not_written; undo.restored=false
X8 independent Classic match: undo.status=unchanged; restored=false; original row and Classic binding retained=true
00:02 +47: All tests passed!
```

日志插入中断使用 SQLite trigger 的 RAISE(ABORT)，证明 Classic 字段更新与撤销证据同事务回滚；移除故障后原 requestId 能重试并正常撤销。撤销回读中断使用端口注入，Classic 已恢复而 outbox 留 pending，关闭并重开夹具运行时后 `media.project` 确认完成。没有声称模拟断电或实际进程崩溃。

正常过程逐列比较整条 `watch_history` 行相等；进度变化过程比较原行加新进度相等；冲突过程比较整表与修改后的快照相等，并核验 Next 绑定已 revoked、identity 冲突可见、重试仍 conflict。二次 bind/undo 和旧请求重试验证可重入及回执隔离。

### 种子发现和落后状态

临时 git 种子和临时 harness 先共享历史，再升级种子；调用只读 status，随后由实验自己 fetch，验证状态改变且用户定制文件内容与 mtime 不变。另一夹具验证没有远端、未 fetch、远端指向另一处时不报“已同步”。端点实验启动临时回环端口，以真实 Python `nipa status` 调用；Dart HttpClient 设置 DIRECT，Python CLI 自身禁用代理。

上述命令的一轮实际输出：

```text
X8 status before fetch: seed=/var/folders/7t/363d2swj60v08tg0lbxg9gnc0000gn/T/harness-upstream-jJj8Gq/seed; state=behind; trackingBehindSeed=true
X8 nipa status: {"status":"running","version":"x8-fixture","repository":"/var/folders/7t/363d2swj60v08tg0lbxg9gnc0000gn/T/endpoint-constraints-X3SuWh/harness","harnessSeed":{"path":"/var/folders/7t/363d2swj60v08tg0lbxg9gnc0000gn/T/endpoint-constraints-X3SuWh/private/harness-seed","head":"e0a8c83527a2e94ba916477bd31fac85c965cab1","remote":"/var/folders/7t/363d2swj60v08tg0lbxg9gnc0000gn/T/endpoint-constraints-X3SuWh/private/harness-seed","remoteMatchesSeed":true,"trackingHead":"f9dead06ffc7fd9dc718681696edf0f81d1d8b70","trackingBehindSeed":true,"state":"behind"},"actions":0,"tasks":{"status":"failed","error":{"code":"not_found","message":"Unknown action: task.list.","retryable":false}}}
X8 status after fetch: state=current; trackingBehindSeed=false; custom file untouched=true
X8 status discovery: missing_remote -> not_fetched; no refs fetched=true
```

端点夹具故意使用空 Harness，故 tasks 子结果为 not_found；种子字段是实际端点返回和实际 CLI 输出，未访问真实应用端点。

### 意外及修正

1. 新回执查询对无投影的 TMDB 文件传了 null SQL 参数，sqflite 提示未来将拒绝此参数；改为无 projection ID 时不查询，无投影结果为空列表。
2. 首轮静态检查有五处单行 if 的 lint，补齐代码块后通过。
3. 首轮全量回归只有“新行保留后续进度”的新增夹具失败：期待 900000，实际 0。macOS 将无原历史的路径规范化为 `/private/var/...`，夹具用 `/var/...` 更新，没命中实际行。改用实际行 ID 并断言更新数为 1；生产投影未因此改动。后续增加原行 ID 比较，覆盖删除后重建相同匹配这一冲突情况。
4. 最终审查补出同集再次投影可能丢掉初次撤销关系的缺陷，增加前一投影继承和三项跨来源夹具。夹具首次按内部 provider/id 字段查 Action 结果，实际接口为 ref.provider/bindingId，导致 No element；后续新增用例又因局部 bind 变量遮蔽 helper 而编译失败。修正夹具字段和变量名后，三项均通过；Classic 编辑后的再次投影和最后撤销都返回 conflict。

### 回归及静态检查

```sh
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next test/watch_history_database_migration_test.dart \
  test/watch_history_model_test.dart test/watch_history_startup_test.dart \
  test/watch_history_legacy_startup_test.dart --reporter expanded

~/development/flutter-3.44.6/bin/flutter analyze --no-pub \
  lib/next/media lib/next/harness_repository.dart lib/next/agent_endpoint.dart \
  test/next/projection_undo_experiment_test.dart \
  test/next/harness_repository_test.dart test/next/agent_endpoint_test.dart \
  test/next/media_classic_projection_test.dart test/next/one_library_experiment_test.dart

git diff --check
```

全量覆盖 Next、真实本地 TLS、Classic 历史迁移与启动；相关范围覆盖原 X5 同集独立匹配、共享库补齐、中断恢复及身份批量原子性。最终输出见下方。

```text
00:26 +354: All tests passed!
No issues found! (ran in 2.8s)
```

`git diff --check` 无输出、退出码 0。没有构建或启动真机新版本、访问线上元数据，也没有对真实用户数据库执行投影或迁移。

## 4. 问题

需要主控决定：**确认受影响构建是否已分发；若已分发，是否安排带候选预览、原值证据和逐项确认的历史数据修复。** 建议修复已确认受损记录，避免自动改动所有空标题。本机已经手工恢复，不需要再次处理。

本次实现及夹具验收没有其他待决定事项。

## 主控答复（2026-10-11）

受影响的代码从未分发：Next 分支没有推送或发布，只在维护者本机运行。本机核对：Classic 中没有“已匹配但标题为空”的行（v1 时期《炒翻天》12 集的投影标题完好），实验 5 写坏的那一行已从备份恢复。不需要历史数据修复。
