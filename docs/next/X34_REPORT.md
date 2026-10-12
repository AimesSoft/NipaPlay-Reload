# X34：界面元数据事实、图片写入与公开链接

2026-10-12，worktree `~/Desktop/nipaplay-next-wt/x34-metadata`，分支 `next/x34-metadata`。证据时间为 UTC。

## 1. 完成了什么

- 种子 AGENTS.md 增加界面所需元数据、各项出现位置和缺省显示的事实，包含横版无文字背景、竖版海报、透明 Logo、简体中文优先的标题/简介、剧集标题/截图、评分及其他作品资料。没有增加检索步骤或来源路线。
- 新增只读 `media.metadata.ui_facts {workId}`：调用同一个 `NextUiData.work/episodes`，给出每项是否可用、实际文字/本地图片路径、来源、简介/标题语言、逐集截图覆盖、优先主视觉图片和 tint。显式保留缺项和 null。
- 新增 `media.artwork.set {entries:[...]}`：作品 backdrop/poster/logo、单集 still，支持 HTTP(S) URL 或绝对本地文件，必须附 `source:{label,url?}`。批量先验证和缓存，再原子写入现有元数据覆盖与编辑审计；activity 可读来源、actor、origin、invocationId。图片独立覆盖，刷新来源不会覆盖它们。
- 确认并说明 `media.metadata.override` 能改 `title` 和 `overview`；新增可选 `language`。正文与语言共享编辑生命周期，未声明语言的新正文不继承旧语言。来源标题/简介优先简体中文，显式编辑仍优先。
- 复用 X26 图片缓存、解码和原子发布；没有背景时从海报计算 tint。独立图片覆盖无需平台身份或 TMDB 凭据，已保存的图片事实也不因缺少凭据而被整份屏蔽。
- 服务端、状态投影和种子 nipa 保留普通公开链接及非秘密查询参数。带 userinfo、令牌、签名、凭据查询/片段及已知秘密仍脱敏；没有修改 Classic 的 SecretRedactor。
- `ui.capture` 默认长边至多 1280 像素，不放大小图；`originalSize:true` 返回原尺寸。结果包含 originalWidth/originalHeight 和实例事实。

接口说明见 [ui_data/README.md](../../lib/next/ui_data/README.md)。没有修改 `lib/next/ui/`、依赖、用户 Codex 配置、登录钥匙串或真实应用数据；没有 commit/push。全部构建在本 worktree，实验直接运行其可执行文件，保持安静，没有激活窗口、像素点击、按应用名查找或启动安装的应用。

## 2. 决策

**图片沿用既有元数据编辑，不新增数据库版本。** 四种图片分别保存为 `artwork.backdrop/poster/logo/still`，值保留 locator 和来源对象；因此已有 persistent 语义、工作/发行视图、来源审计与 activity 均能复用。URL 沿用 X26 的 URL 哈希文件；本地输入按内容哈希复制，原输入删除后仍可用。该本地副本是覆盖引用的保存文件，不能把它与可重新下载的 URL 投影一起当作无来源的临时文件清理。

**不把请求语言当成正文语言。** lab10 的 Bangumi 简介带日文假名，快照却声明 zh-CN。事实返回 `language:ja`、`declaredLanguage:zh-CN` 和 `languageBasis:observed_kana`；没有假名证据时使用声明值，未声明就是 unknown。没有引入翻译、语言模型或繁简转换；语言推断仅提供这个有限的可观察证据。

**只读事实读取界面投影，来源再关联原始记录。** 文字与图片可用性来自 NextUiData，来源来自相同合并元数据；生成的集数注明来自本地剧集目录。读取可能生成可删除的 ui_cache/图片投影，不写入用户编辑或绑定；既有 TMDB 图片读取仍可能取得并追加来源快照，沿用 X26 行为。

**秘密规则同时守住两层输出。** URL 先识别认证组件，避免先替换令牌后破坏 URL 解析；随后沿用已知秘密与命名秘密字段的脱敏。普通 URL 不删查询参数，不重新编码公开地址。Classic 未启用 Next 时的行为不变。

## 3. 实验与真实输出

完整逐次输出见 [operations.json](evidence/x34/operations.json)、[experiment.log](evidence/x34/experiment.log)，全部界面事实与同进程 UiWork 原样输出见 [UI_FACTS.md](evidence/x34/UI_FACTS.md)。真实 Agent 协议轨迹见 [chat-events.jsonl](evidence/x34/chat-events.jsonl.gz)，脚本见 [x34_experiment.py](../../scripts/next/x34_experiment.py)。以下 JSON 是真实输出的字段摘录。

### 实例、选择与隔离

从授权的 lab10 复制临时配置，SQLite 使用只读源连接的 backup；复制配置内的凭据，不输出凭据。对话配置仅写入临时 `codex-home`，公共 CA 副本和 NO_PROXY 按 X23 设置。实际头部：

```json
{"model":"deepseek-v4.1-flash","provider":"cpa","cwd":"~/Library/Application Support/NipaPlay/LabProfiles/x34-36842/harness"}
```

```json
{"pid":36843,"executablePath":"~/Desktop/nipaplay-next-wt/x34-metadata/build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay","windowTitle":"NipaPlay · LAB [x34-36842]","experimentalProfile":true,"profileName":"x34-36842"}
```

VM PID 与 subprocess PID 相同。`labs_use_next_interface=true`，全部截图来自这个实例。

lab10 实际保留了 Bangumi 504950 与弹弹play 17864 两个作品身份，没有 TMDB，海报/简介来自 Bangumi。为严格验证任务要求的“作品只有 Bangumi 身份”，另做了一项独立对照：只在第二个临时副本撤销作品的弹弹play 绑定，保留审计、剧集与文件；不重跑真实 Agent 回合及其他图片角色。其真实 identity 输出摘录：

```json
{"ref":{"provider":"dandanplay","objectType":"anime","externalId":"17864","scope":""},"status":"revoked"}
{"ref":{"provider":"bangumi","objectType":"subject","externalId":"504950","scope":""},"status":"accepted"}
```

对照实例 PID 49351、profile x34-49343，同样通过新能力写入背景与中文简介，再读取事实并截图，结果相同。完整输出和截图见 [Bangumi-only operations](evidence/x34/bangumi-only/operations.json)、[对照修改后截图](evidence/x34/bangumi-only/after.jpg)。

### 修改前：Agent 能知道缺什么

```json
{"overview":{"available":true,"value":"喫茶リコリコを舞台に\r\n千束やたきな達の日常を6本お届けします","language":"ja","declaredLanguage":"zh-CN","languageBasis":"observed_kana"},"backdrop":{"available":false,"path":null,"url":null,"source":null},"poster":{"available":true,"url":"https://lain.bgm.tv/pic/cover/l/01/d5/504950_WmdZx.jpg"},"logo":{"available":false,"path":null,"url":null,"source":null}}
```

```json
{"heroImage":"poster","tint":4294901502,"episodes":{"total":6,"titles":6,"stills":0}}
```

没有背景时 tint 已取自海报，实际为 `0xfffefefe`。类型、制作公司、评分也明确返回 unavailable；不是根据截图猜缺项。

### 真实 DeepSeek 回合：背景与中文简介

用户输入给出官方第 1 集无文字横版剧照和按官方简介翻译的中文正文，没有给能力操作步骤。Agent 自己列能力、定位作品、读 ui_facts、确认 URL 返回 200、调用 artwork.set 和 metadata.override，再读 ui_facts。

真实耗时 **77,787 ms**，20 次命令执行。仍有试错：把 Action 当 state view、shell 串接/引号错误，写 `/tmp/works.json` 被隔离边界拒绝后改用 harness 内文件。它最终根据同源事实说明原简介为日文、背景缺失，并完成两项写入；没有靠截图寻找字段，也没有读取连接令牌。结束输出包括：

```text
背景图当前缺失，简介是日文。先确认官方图片可访问，然后写入。
两项都已写入，用界面同源数据复核。
```

实际复核输出摘录：

```json
{"backdrop":true,"overview":"《莉可丽丝》以六部原创短篇动画回归。故事以莉可莉可咖啡厅为舞台，描绘千束、泷奈与伙伴们一起度过的轻松日常。","language":"zh-CN"}
```

```json
{"heroImage":"backdrop","tint":4283776026,"backdropUrl":"https://lycoris-recoil.com/shortmovie/assets/img/ep01_1.jpg"}
```

这里 backdropUrl 是从真实 `fields.backdrop.url` 摘出的值。tint 为 `0xff553c1a`。

[修改前截图](evidence/x34/before.jpg) 是海报、日文简介和六个缺图剧集；[Agent 修改后截图](evidence/x34/after-agent.jpg) 已显示官方剧照背景和中文简介。人工打开并核对了两张 PNG。本轮给定了图片与正文，因此只证明新事实/入口可被真实 Agent 发现并完成，不证明开放检索任务一定能在同样时间完成。

### 其他图片角色、本地文件与 activity

同一实例一次批量交入本地海报、官方透明 Logo 与第一集截图：

```json
{"status":"completed","result":{"entries":[{"entityId":"work-dcd42b10aa57e918860e51adbff47c206896639bdb20cfbc286870d8df7593aa","kind":"poster","saved":true},{"entityId":"work-dcd42b10aa57e918860e51adbff47c206896639bdb20cfbc286870d8df7593aa","kind":"logo","saved":true},{"entityId":"episode-d91b7b5a3a0fcd032d8a7a043d7afd6fdb158d96b22ee3da83eba34bff845c5c","kind":"still","saved":true}]}}
```

随后删除原海报输入文件；再次读取时 poster/logo/backdrop 均 available=true，still 覆盖 **1/6**，NextUiData 的 next.still 与事实路径一致。[全部角色写入后截图](evidence/x34/after-all.jpg) 已显示 Logo 和第一集缩略图。这个官方 Logo 本身是深色，在深背景下不醒目；后端保存了原图，没有改变其配色。

activity 中背景图来源真实值：

```json
{"type":"metadata.edited","actor":"agent","origin":"harness_cli:chat:nipa-1791785562238502-a9c4c23c","invocationId":"inv-1791785632523223-17","source":"media_metadata_edits","facts":{"field":"artwork.backdrop","mode":"persistent","value":{"url":"https://lycoris-recoil.com/shortmovie/assets/img/ep01_1.jpg","source":{"label":"lycoris-recoil.com 官方短篇第1集剧照","url":"https://lycoris-recoil.com/shortmovie/movie/"}}}}
```

### 链接脱敏和截图尺寸

通过真实 `media.metadata.import_batch → snapshots` 服务端往返，再经临时 harness 的种子 nipa 输出：

```json
{"x34PublicUrl":"https://lycoris-recoil.com/shortmovie/assets/img/ep01_1.jpg?width=1280","x34SignedUrl":"[redacted URL]","x34UserUrl":"[redacted URL]","x34SignatureUrl":"[redacted URL]"}
```

真实令牌探针原文没有出现在输出中；Bangumi 的普通 imageUrl 也已在 Agent 返回值中完整可见。约束测试另外覆盖已知秘密及 URI 编码形式、用户名但无密码、编码的 token 参数名、cookie/authorization 和嵌套 JSON。

实际 ui.capture 输出摘录：

```json
{"bytes":1253147,"width":1280,"height":735,"originalWidth":3024,"originalHeight":1736}
{"bytes":6329977,"width":3024,"height":1736,"originalWidth":3024,"originalHeight":1736}
```

默认 PNG 比显式原尺寸少约 80% 字节。原尺寸文件仅验证尺寸后删除，报告保留默认大小的截图。

### 失败、检查与清理

第一次预检在 facts 的属性解码处报类型错误，尚未启动对话或写入补图；修正后只继续尚未完成的实验。失败输出见 [failed-preflight](evidence/x34/failed-preflight/experiment.log)，其 PID 34644 已退出且 profile 删除。约束测试新增代码最初有缺少 import/静态类型转换的编译错误，修正后相关文件通过。

派生 `package_graph.json` 和 FlutterGeneratedPluginSwiftPackage 缺失，按 X23 只读复制已有解析产物到本 worktree，修正生成文件里的本地插件路径；没有 pub get。构建自动改写的 Podfile.lock 已恢复，最终无依赖 diff。

```text
flutter analyze --no-pub <本次修改的后端文件和新增脱敏测试>
No issues found! (ran in 4.5s)

ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache flutter build macos --debug --no-pub
✓ Built build/macos/Build/Products/Debug/NipaPlay.app

lockf -k /tmp/nipa-next/flutter-test.lock env <去代理> flutter test --no-pub test/next --reporter expanded
01:30 +437 ~4: All tests passed!
```

完整 test/next 只运行一次；其中四个环境条件测试按原规则跳过。相关 metadata_snapshot 检查另通过 7 项，包含 Classic 资料投影不改原缓存；新增图片约束验证整批失败无编辑、来源归属和删除原文件后可用。全量日志见 [full-test.log](evidence/x34/full-test.log.gz)。

实际清理结果：

```json
{"pid":36843,"exitCode":-15,"profileRemoved":true}
{"pid":49351,"exitCode":-15,"profileRemoved":true}
```

所有实验进程均按 PID 退出，没有碰用户正在看的 ui-demo。

## 4. 还缺什么与主控问题

后端目标已完成。实验只补第一集截图，仍有五集截图、类型、制作公司、评分未补，这些都能在事实里直接看见。开放检索任务和不同来源语言声明的质量仍需后续真实使用观察。本轮没有修改界面；海报替补和对话界面的最终整合由主控已有任务负责。

需要主控决定的问题：**没有**。
