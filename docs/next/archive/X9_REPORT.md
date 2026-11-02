# X9：身体接收任意来源的身份与结构化事实

2026-10-11，主仓库 `next/capability-layer`。已阅读 RESEARCH、TEAM、实验 6，以及用户 harness 中的豆瓣工具、存档和经验；harness 只读。

## 1. 完成了什么

- `media.identity.bind_batch` 增加直接绑定模式：`kind`、既有 `entityId`、`ref`、`reason`，可交入任何来源的作品、季、集身份，无需内置 provider 或联网。保留原内置目录绑定、文件关联和 Classic 投影能力。
- 新增 `media.metadata.import_batch`：原子追加结构化快照，支持评分 value/max/count/label、导演、主演、类型，以及完整的其他 JSON 字段。宿主填写评分来源、收到时间、actor、origin、invocationId；调用者不能自报这些审计字段。
- 新增 `media.metadata.snapshots`：读回全部原始快照和审计记录，包括历史版本与已撤销身份对应的快照。
- 身份、作品结构和状态查询新增 `metadataView = {fields, provenance, ratings}`，结构化字段不再降格成文字。旧 `metadata` 文本数组保留兼容。
- work 与 release 共用作品元数据视图；episode/file 仍有自身的元数据。一次作品结构响应复用同一个作品视图。
- Classic 完整详情按弹弹play身份读取作品视图；只有 TMDB 等身份的本地文件，通过 FileEpisode 在现有播放器详情显示评分和简介。主创、评价人数复用制作信息，评分复用已有评分行，没有重做 Classic 界面。
- 补充能力契约到 `lib/next/media/README.md`，新增实验 6 的离线快照夹具与 6 项数据约束/Classic 回归实验。

没有 commit、push、pub get 或依赖修改。没有退出、重启、连接或写入正在运行的真实应用。没有写用户 harness 和 `~/Documents/nipaplay`。开始时已有的 `macos/Podfile.lock` 修改保持原状。

## 2. 决策

### 来源命名空间

保留旧内置名称 `tmdb`、`bangumi`、`dandanplay`。新增来源必须使用 HTTPS origin，例如 `https://movie.douban.com`，不接受 `douban` 这种自由昵称。

宿主统一大小写、前后空白、默认 443 端口、末尾斜线和 hostname 末尾点；拒绝来源中的路径、查询、fragment、userinfo 和空白/转义 host。`HTTPS://MOVIE.DOUBAN.COM:443/` 和规范 origin 得到同一个外部对象。Agent 后续复用身份读回的规范 provider。

不同 hostname/非默认端口代表不同 authority；不凭名字猜测它们是否属于同一站点，也没有新增豆瓣别名表。真实域名拼错会成为不同 authority，无法由应用在离线环境判断；这里通过完整 authority、禁用昵称和复用已读回的引用，消除常见的名称写法分裂。objectType/externalId/scope 是来源内的 opaque 字符串，保留原样。

直接绑定只关联既有实体，不自动建立任意网站的目录或文件映射。外部对象是否与本地实体对应由 Agent 判断，宿主验证实体层级、同来源冲突和同种实体的外部对象唯一归属，并保存证据。内置目录模式仍验证目录成员关系。

### 快照、来源与时间

快照追加存入已有 `media_snapshots`，请求回执存入已有 `media_binding_operations`。评分在快照内保存宿主确定的 source；`ratings` 同时保留各外部对象/语言的最新评分，所以评分不会随其他来源交入而消失。

来源报告的 `fetchedAt` 单独保留；宿主的 receivedAt/recordedAt 决定提交快照的新旧及 correction 是否过期。Agent 交入一个报告为旧年份的快照，也不能伪装成宿主之前收到的事实。原始字段、null、数组、嵌套对象都保留在快照；读回历史不会触发网络请求。

评分满足有限 `0 <= value <= max`、`max > 0`；count 是非负整数或 null。常见字段有类型约束，其余字段开放。import 与 bind 都是批量原子操作，requestId 的回执跨重开保留；不同内容复用 requestId 返回 conflict。

### 一个作品的视图与编辑

以 work 为作品事实的首选层。先取 work 的服务/提交快照，再从 release 补缺项；各层内按快照时间取新值。Classic 观察优先级最低。同一对象/语言只使用最新提交快照，历史全部保留。季自己的标题、简介和其他原始事实可从 snapshots 读取。

work 与所有 release 的既有编辑共同参与作品视图，取该字段 changed_at 最新的有效编辑；同时间优先 work，再按实体 ID 稳定选择。persistent 保留；correction 在作品范围收到更新快照后过期；明确调用 clear 清除作品范围内该字段的活跃编辑，原编辑日志不删除。episode/file 编辑范围保持自身。

这是一条读取规则，没有批量迁移或改写既有 override。实验 6 已经拼进 overview 的持久编辑不会自动拆解或撤销；保留这些编辑是既有语义。清除编辑后才显示来源简介，不需要两层各写一次。

`state.query` 原来会把开放 JSON 对象投影为空。现在只有 schema 显式声明 additionalProperties 的对象保留额外属性，继续递归去掉公共 URL 的认证信息；已有封闭 schema 和秘密字段投影不变。原始快照 Action 可以读取完整来源字段。

### Classic 投影与持久数据

Classic 的详情服务在返回完整详情时叠加作品事实，缓存仍保存原 Classic 模型；本地播放详情增加可选元数据读取回调。没有 Next 事实时原模型原样返回，个人评分保持原值。异来源评分转为 Classic 的十分制显示，原始满分和人数仍在结构化事实中；相同显示名发生冲突时追加来源标签，不覆盖已有评分。

本地路径同时查询原路径和符号链接解析后的路径，避免 macOS `/var` 与 `/private/var` 的夹具路径差异，也覆盖同类真实路径别名。文件对应多部作品时报告冲突，不选择其中一部。

本次不需要 schema 迁移，Next 数据库继续为 v8。既有快照、任务、历史、绑定、回执和编辑行均不重算或批量修改。事务失败回滚整批写入；重开数据库不重复交入数据。旧版本读取时可忽略新增 JSON，原有行仍可恢复。Classic 的持久缓存、历史和个人评分没有被元数据投影改写。

TMDB-only 身份不会伪造弹弹play身份，也没有改造 Classic 海报墙收录规则；本地播放详情已有的概念可以显示。Classic 内存缩略预览仍使用原缓存，完整详情重新读取事实；已经打开的页面没有新增实时推送。沉浸式的 Bangumi 专属评分位保持原义，任意来源评分不伪装成 Bangumi 评分。其余无对应界面概念的事实留待 Next 使用。

## 3. 实验与真实输出

夹具 `test/next/fixtures/media/douban_snapshot.json` 来自实验 6 归档公开事实：subject 26849758、8.1/10、520049 人、主创和简介。把原来的 intro 映射为 overview、year 映射为整数；存档只有采集日期，夹具用当日 UTC 零点表示。`unfamiliar` 是额外构造的未知 JSON 字段，用于观察无损读回。没有重新访问豆瓣。

运行 `test/next/metadata_snapshot_test.dart`，使用真实 NextCore、Harness Action、SQLite、状态查询及 Classic 详情 widget；所有应用数据在系统临时目录，结束删除。先用离线 TMDB transport 建立作品、季、集，初始只有 TMDB 身份；随后直接绑定豆瓣身份，交入快照、重试、读回各入口，再关闭并重新打开夹具数据库。

最后一次组合回归中的原始输出如下：

```text
X9_EXPERIMENT {"initialProviders":["tmdb"],"acceptedProviders":["tmdb","https://movie.douban.com"],"rating":{"value":8.1,"max":10,"count":520049,"label":"豆瓣","source":"https://movie.douban.com"},"ratingProvenance":{"provider":"https://movie.douban.com","source":"submitted_snapshot","language":"zh-CN","fetchedAt":"2026-10-11T00:00:00Z","recordedAt":"2026-10-11T03:08:54.007392Z","snapshotId":"imported-snapshot-70697add053704c140b6079294f89f854fae8c7a65dbd618a8c4771e1d8dfffe","entityId":"work-da83932a3627c208528dc030628300d1b20fab58e03f4a3eb7d6de547873b1a6","actor":"agent","origin":"mcp","invocationId":"inv-1791688134004726-2"},"overview":"改编自马伯庸的同名小说，讲述了唐朝上元节前夕，长安城陷入危局，长安死囚张小敬临危受命，与李必携手在十二时辰内拯救长安的故事。","snapshotProviders":["https://movie.douban.com","tmdb"],"snapshotCount":3,"unknownField":{"nested":[1,true,null,{"key":"保留原样"}]},"workEqualsRelease":true,"consistentEntrances":["media.identity.get","media.library.work","media.entities","library.works","library.seasons"],"retrySameReceipt":true,"oldSnapshotsUnchanged":true,"reopenUnchanged":true,"extraNetworkRequests":0}
X9_CLASSIC_TMDB_ONLY {"ratingText":"豆瓣: 8.1","rendered":true,"dandanplayIdentity":false,"summaryRendered":true}
X9_CLASSIC {"summary":"改编自马伯庸的同名小说，讲述了唐朝上元节前夕，长安城陷入危局，长安死囚张小敬临危受命，与李必携手在十二时辰内拯救长安的故事。","ratingDetails":{"Bangumi评分":7.0,"豆瓣评分":8.1},"credits":["制作: 原制作","导演: 曹盾","主演: 雷佳音、易烊千玺、周一围、芦芳生、热依扎、王鹤润、杰曼·翰苏、韩童生、李媛、余皑磊","豆瓣评价人数: 520049"],"cacheUnchanged":true}
00:04 +109: All tests passed!
```

3 个作品范围快照是 TMDB work、TMDB season、豆瓣 subject；TMDB episode 自己的快照在 episode 范围。作品和季视图相同，集仍保留集简介。原 TMDB 快照逐行相同，重开全部快照逐行相同；绑定和交入豆瓣事实增加的联网请求为 0。

另有约束观察：规范 origin 的等价写法归一；作品/季/集直接绑定成功；来源冲突或重复本地归属使整批回滚；错误评分使整批快照回滚；拒绝伪造 actor；不同请求内容不能复用 requestId。TMDB 与豆瓣两份结构化评分同时保留，撤销豆瓣身份后评分退出当前视图，但原始历史快照仍读得到。release 持久编辑在新快照后保留并同时在 work 可见；clear 后两层都回到源简介；correction 被宿主随后收到的新快照替代，即使其来源采集时间声明为 2000 年。

Classic widget 实验从真实文件索引和 FileEpisode 读出作品元数据，再交给原详情页渲染；为了避免 Flutter fake async 阻塞 SQLite I/O，数据库准备和读取在 tester.runAsync 中执行。渲染用同一读出模型，海报在该评分/简介夹具中留空，不请求图片。没有为观察评分拼接 overview。

### 验证命令与意外

全部命令使用 `~/development/flutter-3.44.6`，Flutter analyze/test 加 `--no-pub`。实验 transport 没有 HTTP 回环访问，未接入真实 endpoint。

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub test/next/metadata_snapshot_test.dart
~/development/flutter-3.44.6/bin/flutter analyze --no-pub lib/next/media lib/next/state lib/models/playback_detail_context.dart lib/providers/service_provider.dart test/next/metadata_snapshot_test.dart
```

新增 6 项全部通过；所列 analyze 范围输出 `No issues found!`。曾分析既有 BangumiService 文件，发现其已有 unused_local_variable、单行 if 和 catchError 返回类型提示；本次新增代码无对应错误，未作无关清理。`git diff --check` 通过。

组合回归覆盖全部 `test/next/media_*test.dart`、X9、state.query、X8 撤销、X5 统一库、Classic lazy cache、metadata sliver，以及沉浸式详情 UI，共 109 项。

第一次直接运行组合回归：107 项通过，两项实验室开关测试因未模拟原生通道失败：

```text
MissingPluginException(No implementation found for method isSandboxed on channel security_bookmark)
00:05 +107 -2: Some tests failed.
```

不修改原测试文件或依赖，在忽略目录 `.dart_tool/x9_immersive_stub_test.dart` 建立临时入口：初始化测试 binding，把 `security_bookmark.isSandboxed` 返回 false，然后调用原 `immersive_anime_detail_ui_test.dart` 的 main；其余原生调用会明确报错。该套件 30 项通过。替换组合命令中的沉浸式测试入口后，109 项全部通过；日志位于 `.dart_tool/x9_verification.log`，上述输出直接摘自该日志。模拟的是单元测试环境的非沙箱平台，没有改变真实应用的沙箱判断。

期间 widget 实验还暴露了 `/var` 路径别名漏查，已修复；最初把真实 SQLite I/O 放进 widget fake async，以及等待图片加载的 pumpAndSettle，会挂起/超时，调整夹具后渲染通过。这些失败没有涉及用户数据。

## 4. 需要主控决定的问题

没有。真实应用仍运行原二进制；本报告验证的是新代码的隔离夹具，未做真机升级或重启。主控后续按团队流程在自己的集成版本做实验即可。
