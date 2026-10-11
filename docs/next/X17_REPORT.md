# X17：远程媒体也能绑定身份

日期：2026-10-11。worktree：`~/Desktop/nipaplay-next-wt/remote-binding`，分支：`next/remote-binding`。

## 1. 完成了什么

`media.identity.bind_batch` 现在接受已登记的 Jellyfin、Emby、SMB、WebDAV、NipaPlay 共享远程文件。远程绑定使用位置与来源证据，复用现有实体、FileEpisode、绑定、审计、操作回执和投影 outbox；本地文件继续执行文件探测及提交前的内容校验。没有下载远程文件，也没有根据名称自动识别。

内置目录来源继续使用 `workRef/releaseRef/episodeRefs`。任意 HTTPS 来源新增文件的直接引用形式：`kind=file + entityId + ref + localEpisodeIds:[episodeId]`；ref 必须已经 accepted 在指定的本地 Episode 上，可在同一个 batch 的前一条显式绑定。这个形式不请求新客户端、不生成空快照、不推断外部目录关系。批量原子性、同来源冲突、已有文件集关联、来源记录、幂等与撤销仍由同一存储层约束。

单集弹弹play绑定写入 Classic 已有 `jellyfin_dandanplay_mapping/jellyfin_episode_mapping` 或对应 Emby 表；Classic 映射服务、播放列表和集导航能够消费这些结果。TMDB、Bangumi、其他来源留在 Next。SMB、WebDAV 和共享 HTTP 流的弹弹play身份继续走已有观看历史投影。

新增远程映射的写入与撤销证据在 Classic 同一事务内提交；撤销只收回自己的写入。独立同集匹配保留，Classic 编辑、重匹配或删除后的数据保留并返回可见冲突。原 requestId 的回执可重入，投递与撤销的读回中断能够通过原 outbox 恢复。

没有修改依赖、运行 pub get、commit 或 push。没有在主仓库构建，没有启动 NipaPlay.app，没有读取或写入用户登录钥匙串、真实应用数据目录。所有数据库实验使用临时目录、SharedPreferences mock、内存保险库和 `StorageService.debugAppStorageDirectoryOverride`；实验目录已经删除。本次没有构建或启动 GUI 窗口。

## 2. 决策

### 身份确认与本机字节读取分开

实验 9 的错误来自 `MediaService.readFile`：文件绑定也要求本机位置和本机 probe。新增绑定专用的位置读取；本地文件仍走原 readFile，远程文件读取登记的当前位置及已有 probe，缺少哈希时保留缺失值。哈希匹配仍需要本机文件。远程文件的正式身份是 Agent 明确提交的关联，不冒充由字节验证得到的身份。

远程文件必须已经登记。未登记的远程 path 返回 not_found；没有本设备位置返回 unavailable；同一路径对应多个来源返回 conflict，要求使用来源浏览返回的 fileId。绑定审计保存远程来源及 locator 的快照，和本地绑定一样保留 actor、reason、evidence、revision、origin 与 invocationId。

### 服务器范围属于身份定位，播放路径保持 Classic 格式

Next 的远程位置按来源、设备、locator 查询，不再把 `emby://123` 这种路径独自当成全局唯一文件。

| 位置 | 隔离依据 |
|---|---|
| Jellyfin / Emby Next 文件 | sourceId、实际 serverId、ownerDeviceId、locator |
| Jellyfin / Emby 新 Classic 映射 | profileId、实际 serverId、itemId；编码后存入既有条目 ID 列 |
| SMB / WebDAV / 共享媒体 Next 文件 | sourceId、ownerDeviceId、locator |

Classic 新键使用保留前缀 `next:` 和 URI component 编码，profile/server 范围是规范 JSON 二元组。返回给 Classic 消费者时解码回真实 item/series ID。读取器按当前连接范围查询，缓存也包含该范围；投影及 Classic 匹配写入使缓存失效。不同 profile 的相同 item ID，以及同一 profile 改指另一实际 serverId，都不会复用旧 Next 文件或新映射。

不修改旧的无来源归属位置或旧映射，不把它们归到当前连接。旧剧集映射没有服务器归属时，Next 身份可以提交，但 Classic 投影明确返回 conflict，保留原值。无法从这种旧记录证明它属于哪台服务器；自动认领会把已知 Emby 碰撞带入新模型。

Classic 的历史及播放 path 仍沿用原格式，原 Classic 多服务器历史路径碰撞未作数据迁移。Agent 绑定用 browse/sync 返回的 fileId；按 path 有歧义时明确失败。Classic 页面读取新版映射则按其当前服务器范围隔离。本次保证的是新增文件身份与映射的服务器隔离，不宣称已经迁移所有旧历史或改变播放连接选择。

### Classic 已有概念写回既有表

复用原 Jellyfin/Emby 映射表定义，提取共用建表函数；不新建另一套媒体服务器匹配系统，不改表版本或依赖。Classic 没有开启 Next 时，其旧记录和旧读取路径照常使用。存在新版映射时，用户手动重匹配也写到该作用域 episode 键，保证 Classic 的新选择可读，Agent 撤销能检测到变更。

实测服务器的六个条目都是 Episode，有 IndexNumber，但没有 SeriesId/SeasonId。旧映射表要求目录锚，因此没有系列归属的独立文件使用 `item:<itemId>` 作为锚；不猜测六个文件属于同一系列。本轮产生六条目录映射和六条集映射。具有真实 SeriesId/SeasonId 的文件按其真实目录复用映射。

播放列表及导航优先消费 exact episode mapping 的 anime ID，避免从系列默认映射拿到另一个目录的作品 ID；没有新增映射的旧路径继续使用原查询。服务器返回的 ID 在这些消费者处保持原格式。

### 沿用 X5/X8 的持久 outbox 和原子前像

远程日志 `next_remote_projection_journal` 保存 projectionId、locator、服务器作用域集键、完整集行前像/后像、完整目录行前像/后像及状态。表首次投递时创建；Next schema 仍为 8，Classic user_version 仍为 2。

- 新集映射及目录映射与日志同事务提交，日志失败则全部回滚。
- 已有独立同集匹配只登记 unchanged；不改字段、时间或确认标记，不在撤销时删除。
- 新集映射撤销核对完整后像，包括原行 ID。目录被改过也返回 conflict。最后一个集引用退出时，才收回 Next 自己新建的目录；仍有其他引用时保留。
- 同一集因其他来源而重复投影，继承最初前像。发生 Classic 编辑时仍保存原撤销关系，不把再次投影的失败误报成从未写入。
- 已经写入或撤销、尚未完成 Next 回读的窗口，由原 outbox 与日志重试确认；不伪造跨数据库事务。

Jellyfin/Emby 投影不创建或修改 watch_history 行，因此不碰观看进度、缩略图和历史媒体定位。冲突消息继续明确区分 Identity committed / Next bindings revoked 与 Classic 投影失败。

## 3. 实验

### 临时 Jellyfin 与线上弹弹play

`test/next/remote_binding_real_experiment_test.dart` 使用 `/tmp/nipa-next/testservers.json` 指定的 `127.0.0.1:8096`，实际登录、浏览《莉可丽丝》六集。弹弹play通过生产 `DandanplayService` 登录、`NipaplayServerRouter`、`DandanplayHttpClient`、`DandanplayGateway` 和生产元数据 provider 搜索并查询目录，不另写客户端或读取真实登录态。密码与令牌只进入内存保险库，没有输出。

本机没有提供 TMDB API key，未查找用户秘密。本轮 TMDB 使用项目现有离线目录 fixture，通过生产 `TmdbMetadataProvider` 和同一 Action 将真实 Jellyfin 文件绑定到 TMDB 身份，验证 accepted、FileEpisode、无 Classic 投影及撤销。该 fixture 的 9001/9101/9201 是测试身份，不是对《莉可丽丝》的线上 TMDB 识别；本次没有证明 TMDB 线上元数据查询可用。

命令：

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  --dart-define=NIPA_X17_REAL=true \
  test/next/remote_binding_real_experiment_test.dart --reporter expanded
```

HttpClient 对回环地址明确使用 DIRECT；外部服务保留本机代理设置。以下为最后一次真实输出：

```text
X17 live Jellyfin: endpoint=127.0.0.1:8096; login=succeeded; episodes=6; numbers=[1, 2, 3, 4, 5, 6]; kinds=[Episode]; scopedFiles=6
X17 live Dandanplay search: [{"id":"17097","title":"莉可丽丝"},{"id":"17864","title":"莉可丽丝 新作"}]
X17 live bind/readback: {"acceptedFiles":6,"classicAnimeRows":6,"classicEpisodes":[{"number":1,"animeId":17097,"episodeId":170970001,"confirmed":1},{"number":2,"animeId":17097,"episodeId":170970002,"confirmed":1},{"number":3,"animeId":17097,"episodeId":170970003,"confirmed":1},{"number":4,"animeId":17097,"episodeId":170970004,"confirmed":1},{"number":5,"animeId":17097,"episodeId":170970005,"confirmed":1},{"number":6,"animeId":17097,"episodeId":170970006,"confirmed":1}],"primedNegativeCacheBypassed":true,"watchHistoryUnchanged":true}
X17 live undo: restored=6; animeTableEqualsBefore=true; episodeTableEqualsBefore=true; ClassicReadback=null
X17 live remote + TMDB fixture: binding=accepted; provider=tmdb; localEpisodeLink=true; classicProjectionId=null; ClassicTablesUnchanged=true; metadata=offline-catalogue-fixture
X17 live Classic manual rematch: production recordEpisodeMapping readback=170970002; Agent undo=conflict; Classic rematch preserved=true
X17 live cleanup: both foreign_key_check=[]; no accepted file bindings remain; temporary directory removed by teardown
00:05 +1: All tests passed!
```

Classic 读回实际调用 `JellyfinEpisodeMappingService.getEpisodeMapping/getAnimeMapping`，先缓存负查询，再绑定并读回。撤销比较原两张表的整表结果相等。另用生产 `createOrUpdateAnimeMapping/recordEpisodeMapping` 手动改第一集到 170970002，核对 Classic 实际读回新值，并确认 Agent 撤销返回 conflict，Classic 行未被改写。

这证明生产映射读取接口和其播放消费路径能够使用写回结果；没有打开真实 GUI 页面或在窗口中观察弹幕播放。SMB/WebDAV/共享来源的网络连接本轮没有重跑，身份与撤销的数据约束在下述 SQLite 夹具中验证。

### SQLite 数据约束与恢复

`test/next/remote_binding_test.dart` 使用生产 WatchHistoryDatabase、Next SQLite、MediaCapability、MediaService、WatchHistoryMetadataPort。元数据来自明确的离线 fixture；时长探测器直接抛错，远程绑定成功说明不触发本机内容探测。

```sh
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/remote_binding_test.dart --reporter expanded
```

实际输出：

```text
X17 sources: Jellyfin/Emby/SMB/WebDAV/shared identity accepted; undo/replay=true; receipts after restart=10; foreign_key_check=[]
X17 isolation: identical Jellyfin/Emby IDs -> distinct files and Classic mappings; ambiguous path=conflict; undo A preserves B=true
X17 Classic edit: secondary projection=conflict; undo=conflict; Next revoked=true; edited Classic rows unchanged=true
X17 arbitrary source: HTTPS opaque episode ref accepted on all five remote source types; same local Episode/provenance=true; mismatched ref rejected atomically=true; no provider fetch
X17 server replacement: same profile + same item ID + different physical server -> distinct files/mappings; undo old server preserves new server=true
X17 independent Classic: bind/undo preserves complete original rows=true; undo.status=unchanged; TMDB projection=null
X17 remote readback interruption: bind committed once=true; undo already restored before restart=true; pending outbox recovered; persisted receipt.restored=true
X17 interruption: Classic schema/mapping/journal rolled back=true; Next binding durable=true; same request retry/undo=true
00:00 +8: All tests passed!
```

中断使用 SQLite trigger 的 RAISE(ABORT) 或回读器返回失败，不声称模拟断电。重启测试关闭并重开 Next 数据库与服务，核对原操作重试、Classic 行不重复和持久撤销回执。

### 回归、静态检查与清理

完整回归命令：

```sh
env -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next test/watch_history_database_migration_test.dart \
  test/watch_history_model_test.dart test/watch_history_startup_test.dart \
  test/watch_history_legacy_startup_test.dart --reporter expanded
```

```text
00:29 +394 ~3: All tests passed!
```

三项需要显式启用的实验默认跳过；X17 的真实实验另行运行。该全量回归之后追加了远程读回中断夹具（单文件 8 项通过），并针对 Classic 手动重匹配补齐了写入定位及 nullable season 查询；生产真实实验再次通过。X5/X8、本地身份批量原子性、Classic 历史迁移与启动均在完整回归及相关范围中通过。

最终相关静态检查覆盖 `lib/next/media`、媒体来源服务、两种 Classic 映射服务、作用域辅助器、集导航及新增测试：

```text
No issues found! (ran in 2.9s)
```

把 playlist_menu.dart 加入检查时，有四条既有 info：两条 use_build_context_synchronously、两条 prefer_const_constructors，均在本次未修改的代码段；没有新增错误或 warning。没有顺带修改这些代码段。`git diff --check` 通过。

输出检查和实验目录清理的实际结果：

```text
X17 output secret check: no configured passwords/tokens present
X17 remaining experiment directories: 0
```

### 意外与修正

1. 最初把所有 HttpClient 都设为 DIRECT，回环读取成功但外部登录等待过久。修正为只对回环使用 DIRECT，外部保留环境代理；随后线上搜索与目录读取成功。
2. 实际 Episode 条目有集号，但没有 SeriesId/SeasonId，首次实验在系列字段强制转换处失败。改为独立文件目录锚，实际产生六条目录映射，不根据文件名编造系列归属。
3. 首次独立文件的 nullable season 查询产生 sqflite 的 null whereArgs 提示。新查询按 null 使用 IS NULL，避免把 null 作为查询参数；最后一次真实输出没有该提示。
4. 新测试最初误用 Failed.error 和 identity.get 顶层字段；修正为 Failed.failure 与返回的 identity 字段后通过。实现没有因此改变回执契约。

## 4. 问题

需要主控决定的问题：**没有**。

验证边界已明确：真实 Jellyfin与线上弹弹play完成绑定、Classic 读回和撤销；真实远程文件的 TMDB 绑定使用离线目录，未验证线上 TMDB API。旧 Classic 无服务器归属记录保留，不自动迁移。GUI 窗口和真实用户数据库不在本次实验范围内。
