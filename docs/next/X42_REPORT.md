# X42：弹幕内容从数据库移到文件

2026-10-13，worktree `x42-danmaku-files`，分支 `next/x42-danmaku-files`。
没有 commit、push、pub get、新依赖、下载/字幕或 `lib/next/ui/` 改动。

## 1. 完成了什么

- `danmaku.import`、在线分段获取和播放回写的 Next 内容都保存为
  `next/danmaku/<sha256>.json`。写入、flush、回读校验、原子换名后，数据库事务才提交引用和绑定。
- `danmaku_cache_chunks` 保留 cache key、范围、覆盖、时间，并增加相对路径、条数、字节数与
  `storage_kind`。大 `payload` 改为 `[]`；来源及审计仍在绑定和事件中。
- 播放、热度、主视觉、`ui_facts`、导出经统一存储读取；读取校验哈希、字节数与条数。
  `state.query(danmaku.datasets)` 直接给出文件事实和真实条数，不再对空 payload 计数。
- 数据库 v15 迁移先追加字段，再逐行将旧 JSON 原样发布为文件。每行独立提交，异常/中断后
  保留已完成引用与未完成 JSON；下次打开续迁。全部完成后执行 VACUUM，整理标记成功后才清除。
- 刷新、撤销释放无其他 accepted 绑定引用的交入池；共享文件等最后一个数据库引用释放后删除。
  启动与后续清理会收集事务回滚/中断遗留的无引用文件。
- 新增 `danmaku.cache_prune`，按独立文件实际字节回收最旧可获取缓存；默认 128 MiB，启动也执行。
  有未结束的获取任务时延后；导入唯一副本不参与预算。被回收池的绑定指针清空，Action 刷新播放。
- 更新种子弹幕一条的存储位置及生命周期事实，以及弹幕 README。

实现入口：[files.dart](../../lib/next/danmaku/files.dart)、
[store.dart](../../lib/next/danmaku/store.dart)、
[next_database.dart](../../lib/next/next_database.dart)。
实验脚本：[x42_experiment.py](../../scripts/next/x42_experiment.py)。

## 2. 决策

**所有 Next 内容使用文件，唯一副本与缓存分别标记。** 显式交入为 `imported`；在线分段和
`application:playback` 回写为 `cache`。它们的文本都是数据库体积来源，统一存储便于统一读取与
文件回收。Classic 现有弹幕缓存仍归 Classic 管理，没有改其取得、存储或关闭 Next 时的行为。
旧 `importedPool` 只有在所有关联绑定都明确记为 playback 时才判为 cache；无绑定或来源不确定
时保留为 imported，避免把唯一副本误当缓存。

**相对引用与按字节内容哈希。** 文件名含平台/视频等完整序列化内容的哈希，相同内容可共用；
文件路径不依赖配置目录的绝对位置。发布、读取与收集使用同一数据库事务串行边界，避免回收
正在提交或读取的文件。新内容编码/写入和旧内容迁移写入在 isolate 里完成；旧 JSON 不重排、
不去重、不丢字段。损坏或缺失的 imported 文件明确失败，不把唯一副本丢失解释为空弹幕。

**逐行迁移，最后整理一次。** 不在 schema 升级的一个大事务中复制整库；v15 字段升级完成后，
逐行续迁再进入运行时。文件失败时未完成行的 JSON 仍在库中，已完成行指向已验证文件。
VACUUM 的持久标记在成功后清除，整理失败/中断下次重试；因此释放页面会真正缩小数据库，
不是只降低逻辑 payload 大小。这会占用启动时间和 SQLite 整理所需临时空间，本轮未测 263 MB
真实用户库，也没有访问它。迁移故障返回错误并关闭数据库，不吞掉错误继续启动。

**清理只释放明确替换/撤销的导入池。** 迁移时保留既有无绑定、包括曾经撤销的 imported 行，
因为它们可能是仅剩的副本；本轮“迁移不丢任何一条”的核对包含这些行。需要主动删除这种旧池
时，现有 destructive `danmaku.cache_delete(cacheKey)` 可以明确指定删除。新轨道刷新/撤销会
自动释放旧交入池；审计事件继续保留。缓存预算计共享文件一次，与 imported 共用的文件不算
可回收字节。有活动获取任务则整轮回收延后，避免破坏已提交分段与续传回执。预算在启动或调用
清理 Action 时执行，长时间运行中不是每次写入后的硬上限。

**备份与多端同步：目前没有覆盖，已如实写明。** 检查了 `ClassicOperations` 的 `backup.*`、
`FullBackupService.collectBackupData`、`BackupCategory`、`SyncService` 与 Classic 增量同步。
现有五类为 preferences、mediaLibraries、watchHistory、episodeMatches、accounts，原本就不包含
`next.db` 或 `next/artwork/`，也不包含新的 `next/danmaku/`。Mesh 调用不是文件复制/数据同步。
本轮没有扩展 Classic 备份格式或同步协议；只拷数据库已不能保留交入弹幕。离线备份 Next 应在
退出应用后同时保留 `next.db` 与 `next/danmaku/`（以及其他 Next 资产目录）。这一事实已写入
[弹幕 README](../../lib/next/danmaku/README.md)。

## 3. 实验与验证

全部实例直接启动本 worktree 的 Debug 可执行文件，临时 `NIPAPLAY_PROFILE`，默认安静、
音量 0，无激活、像素点击、截图或安装版启动。CODEX_HOME、公共 CA 副本、NO_PROXY 均位于/
指向实验配置；实验配置模型写为 `deepseek-v4.1-flash`。本轮通过实际能力调用，没有模型对话，
没有复制用户 auth/config 或修改 `~/.codex`。未访问登录钥匙串、真实应用目录、ui-demo 或主控实例。

### 三集真实 XML，副本删除后读取

只读枚举 `/Volumes/Media/长安十二时辰`，读取前三集 XML，复制这三份到实验 harness 的
`records/`；未复制任何 SMB 视频，也没有整季复制、改名、写入、删除源文件、查询账号或重新挂载。
播放器使用配置内合成的三段 3000 秒纯色视频，合成的作品/剧集身份只在停止的实验配置里建立。
这是实际播放器挂载和读取实验，不是整集真实视频观影验收。

原始输出：[operations.json](evidence/x42/operations.json)、
[experiment.log](evidence/x42/experiment.log)；摘要：[summary.json](evidence/x42/summary.json)。

| 观察 | 真实结果 |
|---|---:|
| 第一、二、三集交入条数 | 16,203 / 17,089 / 13,371 |
| 初次合计 | 46,663 |
| 内容文件数量/字节 | 3 / 14,152,438 |
| 此时数据库大小 | 311,296 字节 |
| 热度 | 三集均 60 段 |
| 删除 XML 副本后第一集播放器轨道 | 1 条 youku 轨道，16,203 条内容 |
| 导出 raw 的回执 | count=16203，bytes=8660618 |
| 第一集刷新 | revision=1、count=1；旧文件不存在 |

数据库每行 `payload="[]"`、`entry_count` 与文件数组长度一致、文件名与内容 SHA-256 一致。
三个副本删除后仍挂载，证明读取不依赖交入路径。`ui_facts` 给出三集弹幕覆盖；主视觉读取到：

```json
["2019年06月29日打卡~","2019年07月03日举手~","2019年07月04日打卡~","周末举手~","四川人民发来贺电","坐标东北打卡"]
```

### 旧格式迁移与真实大小

在上述已停止的临时配置中，用已验证的文件原文重建 v14 的 inline 行，移除文件/新增列与整理
状态表，然后启动最终构建。没有读用户库，没有对另一个实例做 backup。此时第一集已刷新为
1 条，第二、三集仍为完整真实池。

真实输出：

```json
{"beforeBytes":14761984,"afterBytes":311296,"beforeCount":30461,"afterCount":30461,"allContentHashesUnchanged":true}
```

三行条数为 `1 / 17089 / 13371`，前后都为 30,461；每个原 JSON 的哈希均原样保留。
数据库从 **14,761,984 字节（14.08 MiB）缩到 311,296 字节（304 KiB）**，减少约 **97.89%**。
内容目录为 9,251,177 字节，数据搬到文件并没有消失；前后数据库大小还包含旧空闲页，不能将
减少的全部字节解释为净弹幕文本大小。迁移后的 `ui_facts` 与三集热度仍可读取。
`danmaku.cache_prune(maxBytes=0)` 返回 `deletedPools=0,reclaimedBytes=0`，三份 imported 文件均保留。

### 播放中的刷新、失败与不确定性

三集实验中的刷新持久写入成功、旧文件已删除，但当次返回 `loaded=false`，紧接着的播放器
轨道查询为空；没有取得当时的完整播放器状态，原因未定位。不把这次输出当作即时挂载的证据。
只补做相关的 File 和 Episode 合成小池实验，没有重跑三集 XML/迁移：

- File 目标播放中从 1 条刷新到 2 条：`revision=1,count=2,loaded=true`；实际 `playback.tracks`
  返回同一 binding 的 `count=2`，文件目录仅剩新文件。见
  [experiment-refresh.log](evidence/x42/experiment-refresh.log)、
  [operations-refresh.json](evidence/x42/operations-refresh.json)。
- Episode 目标暂停、raw 导出后从 1 条刷新到 2 条：同样 `loaded=true`，实际轨道 `count=2`，
  `playback.state` 仍为同路径的 paused/hasVideo=true。见
  [operations-episode-refresh.json](evidence/x42/operations-episode-refresh.json)。最后额外的 Python
  只读 SQLite 快照遇到 `database is locked`，因此该实验的文件大小断言没有完成；已保留
  [失败日志](evidence/x42/experiment-episode-refresh.log)。脚本后续改为先停止实例再读快照，
  未为了补这个辅助快照重复已成立的挂载实验。

第一次三集 fixture 将集号写成整数，`ui_facts` 按既有字符串契约报类型错误；当时导入已成功，
隔离配置按收尾规则删除。修正 fixture 后完成上面的三集实验；原失败输出保留在
[operations-fixture-failure.json](evidence/x42/operations-fixture-failure.json)。

### 数据约束、构建与收尾

新增五项数据约束测试：共享文件只在最后引用释放后清除；cache 预算排除 imported；活动获取
保护分段；第二行失败后续迁原文/条数一致并整理；数据库提交失败保留旧绑定/引用且损坏文件
明确失败。初始编译缺少构造参数、迁移 isolate 闭包误捕获数据库，以及版本断言仍为 14 的失败
日志均保留；修正后相关测试通过。所有已发布迁移函数保持原位，追加 v15。

- [相关存储/迁移](evidence/x42/related-storage.log)：30 项通过；
  [消费/绑定相关](evidence/x42/related-readers.log)：49 项通过（与前者有重复文件）。
- 按 TEAM 排队、去代理的完整 `flutter test --no-pub test/next` **只运行一次**：
  **455 通过、4 跳过，1 分 36 秒**。见 [full-next.log](evidence/x42/full-next.log)。
- [Classic 自动策略、XML、轨道时间测试](evidence/x42/classic.log)：15 项通过。
- [analyze](evidence/x42/analyze-final.log)：No issues found；
  [最终 Debug 构建](evidence/x42/build-final.log) 成功，Flutter 3.44.6、`--no-pub` 与指定 Erika 缓存。
  [签名](evidence/x42/signature.log)为 ad-hoc hardened runtime，deep/strict verify 通过，
  allow-jit 存在且无 app-sandbox。构建后只有等价格式收敛、文档/实验脚本变化；未重复构建/实验。
- Podfile.lock 的构建生成变化已恢复；保留任务允许忽略的 GeneratedPluginRegistrant 变动。
  `git diff --check` 通过。
- 所有记录的实验 PID 已退出，配置目录最终均不存在，见 [cleanup.json](evidence/x42/cleanup.json)。
  清理复查发现小池配置曾被晚到的 Codex session flush 重建出 codex-home；确认原 PID 已退出且
  无该目录的打开文件后删除仅该实验残留，脚本补上退出前关闭实验 chat host。
  三个 SMB XML 再次只读核对的 SHA-256 与最初一致。
  [证据检查](evidence/x42/evidence-audit.json)中私钥块、带 userinfo 的 URL 与未脱敏 Bearer
  值匹配数均为 0；检查仅记录计数。

未另外验收真实弹弹play服务器抓取/自动播放回写或 263 MB 用户库的迁移性能；这些路径使用
同一文件存储，相关合成测试通过。备份与同步的 Next 全量覆盖仍未提供。三集实验的当次刷新
未挂载现象也仍需在更完整的播放器状态观察中定位，独立 File/Episode 即时刷新已验证。

## 4. 问题

需要主控决定的问题：**没有**。合并并行数据库升级时，按团队约定保留已发布迁移位置，并将
新增迁移放进共同序列末尾。本轮没有进入 X40、X41 或界面工作范围。
