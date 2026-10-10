# 多平台弹幕解析与聚合调研

> 调研日期：2026-10-10  
> 设计基线：`docs/next/DESIGN.md`  
> 范围：只读代码调研与公开资料核对；未修改文件，未读取凭据、配置文件或浏览器数据，未执行带登录态的线上弹幕请求。

## 0. 结论与证据口径

**建议复用现有播放器多轨，新增独立的 `DanmakuSource` 获取层、来源缓存和媒体绑定层，再通过 Harness 暴露给 GUI 与 Agent。** 当前多轨已经支持启停、合并、独立偏移和导出；主要缺口是平台定位、来源溯源、分段完整性、凭据隔离及绑定持久化。证据：`lib/utils/video_player_state/video_player_state_danmaku.dart:522`、`:633`、`:747`、`:1328`。

**弹弹play已经提供第三方关联弹幕聚合。** NipaPlay请求时开启了 `withRelated=true`，但随后把条目统一标为 `dandanplay`。因此，新增B站、优酷直连来源时，需要处理与已有聚合轨道的重叠，不能把它们视为必然互不重复的数据。证据：`lib/services/dandanplay_service_io.dart:1671`、`:1721`、`:1745`；[弹弹play官方接入说明](https://doc.dandanplay.com/open/#_2-使用节目编号获取弹幕)。

**优酷参考实现可以作为首个原生适配器的输入，但不能原样迁移为生产契约。** 它已实现分集查询、按分钟拉取、签名和XML导出；没有完整实现业务错误校验、令牌刷新、分段重试、取消与检查点恢复。尤其是缺失结果字段可能被当作空列表，需要先修正成功语义。证据：`download-harness/danmaku.py:54`、`:77`、`:100`、`:119`、`:155`。

本文采用以下标记：

- **已核实事实**：本地代码或引用的公开资料明确支持。
- **公开实现事实**：核实了开源代码采用的接口与机制，不能据此保证当前线上可用。
- **推测**：尚未验证的运行行为、效果或稳定性判断。
- **提案**：建议的模型、契约和实施方式，不表示已经实现。

本仓库证据采用仓库根目录相对路径的 `file:line`。`download-harness/` 指 `~/Documents/ChatGPT/download-harness/`。公开代码链接通常指向可变分支；本次未完成六个平台的线上可用性与权限矩阵验证。

---

## 1. NipaPlay现有弹幕链路

### 1.1 获取、匹配与第三方聚合

| 环节 | 已核实行为 | 证据 |
|---|---|---|
| 匹配入口 | `DanmakuMatchingService`封装文件匹配、搜索及获取，并集中执行访问策略 | `lib/services/danmaku_matching_service.dart:14`、`:19`、`:131` |
| 播放器加载 | 先读缓存，未命中后检查访问能力，再请求弹幕 | `lib/utils/video_player_state/video_player_state_danmaku.dart:343`、`:413`、`:433` |
| 获取接口 | 调用 `/api/v2/comment/{episodeId}?withRelated=true&chConvert=...` | `lib/services/dandanplay_service_io.dart:1663` |
| 服务选择 | 支持用户选择的兼容服务器；服务地址由服务器路由器决定 | `lib/services/dandanplay_service_io.dart:200`、`:1574` |
| 数据标准化 | 将弹弹play的 `p`、`m` 转换为时间、模式、颜色、文本，保留部分身份字段 | `lib/services/dandanplay_service_io.dart:1721` |
| 来源标记 | 格式化后的条目统一写入 `source: dandanplay` | `lib/services/dandanplay_service_io.dart:1737` |
| 播放器轨道 | 获取结果进入固定的 `dandanplay` 轨道 | `lib/utils/video_player_state/video_player_state_danmaku.dart:373`、`:457` |

弹弹play官方文档明确说明，`withRelated=true`用于获取整合第三方网站后的弹幕。因此，NipaPlay已经消费上游聚合能力；这不等于NipaPlay已经拥有各平台可独立管理的 `DanmakuSource`。官方聚合也不保证每一集都关联了用户指定的平台。证据：[弹弹play官方接入说明](https://doc.dandanplay.com/open/)、`lib/utils/video_player_state/video_player_state_danmaku.dart:457`。

需要区分**上游API要求**与**NipaPlay访问策略**：官方文档把获取弹幕归为公开接口，同时规定应用身份接入；NipaPlay的内置网关客户端另有用户登录检查。兼容第三方服务器使用不同的访问判断，不能把NipaPlay网关的登录要求推广到所有平台。证据：[弹弹play官方权限说明](https://doc.dandanplay.com/open/#_8-api-权限和使用范围说明)、`lib/services/dandanplay_http_client.dart:57`、`test/danmaku_matching_access_test.dart:86`。

**提案：** 将弹弹play封装为一个“聚合型来源”，声明 `aggregation=true`、`compositionKnown=false`，默认保留现有行为。没有获得条目级来源证据时，不把其内容拆成虚构的平台轨道。依据：现有格式化代码统一覆盖来源，见 `lib/services/dandanplay_service_io.dart:1745`。

### 1.2 本地文件导入

手动导入入口支持XML和JSON。JSON支持顶层数组、`comments`数组、`data`数组，以及字符串形式的数组。字节读取还处理UTF-16 BOM、UTF-8及声明编码/GBK回退。证据：`lib/utils/local_danmaku_file.dart:7`、`:32`、`:60`。

自动加载会扫描本地视频所在目录，按同名和弹幕关键词评分，最多尝试八个候选，只自动加载最匹配的一份；HTTP、媒体服务器和部分远程来源不走此目录扫描。证据：`lib/utils/video_player_state/video_player_state_danmaku.dart:140`、`:175`、`:216`、`:248`。

`loadDanmakuFromLocal`可追加多个轨道，记录名称、`source: local`、可选文件路径、条目及数量。因此，可复用其轨道装载思路，但平台来源不宜长期伪装为本地文件来源。证据：`lib/utils/video_player_state/video_player_state_danmaku.dart:522`、`:583`。

### 1.3 格式解析与导出

| 格式 | 已核实能力 | 限制与复用判断 |
|---|---|---|
| B站格式XML | Dart XML解析及容错回退；非Web路径还有C++解析 | 可复用格式解析，但不能以XML格式推断真实平台 |
| JSON | Dart标准化及C++优化路径，支持既有字段别名并透传额外字段 | 可作为统一模型到旧播放器的兼容层 |
| ASS | 将过滤后的弹幕转换为ASS，提供Rust路径及Dart回退 | 已核实为输出能力；现有本地弹幕入口不接受ASS |
| 平台protobuf/压缩包 | 已查看的现有解析入口为XML/JSON | 应新增平台解码器，不能直接交给现有XML/JSON解析器 |

证据：`lib/utils/danmaku_xml_utils.dart:25`、`:57`；`lib/utils/danmaku_parser.dart:46`；`lib/cpp_native/bindings/danmaku_parser_io.dart:139`；`cpp_native/src/danmaku_parser.cpp:552`；`lib/utils/danmaku_ass_converter.dart:124`；`lib/utils/local_danmaku_file.dart:10`。

XML解析存在明确的来源误标：Dart与C++实现都把B站格式XML条目标为 `bilibili`。harness输出的优酷XML采用同一格式，因此会遇到相同问题。证据：`lib/utils/danmaku_xml_utils.dart:137`、`cpp_native/src/danmaku_parser.cpp:241`、`download-harness/danmaku.py:155`。

**提案：** 区分 `format=bilibiliXml` 与 `platform=youku`。解析器负责格式；平台身份由来源绑定或导入元信息赋予。旧XML没有可靠元信息时，平台记为未知，不根据文件格式补造。依据同上。

现有 `DanmakuMode`保存普通、底部、顶部、逆向和高级模式，但显示类型只有滚动、顶部、底部；逆向与高级模式会降级为滚动。首批来源应明确声明支持的模式，不能声称已经完整支持BAS或代码弹幕。证据：`lib/constants/danmaku/mode.dart:6`、`:26`。

### 1.4 多轨、过滤、合并与偏移

`VideoPlayerState`公开轨道表与启用表。合并过程遍历启用轨道，应用轨道偏移，按时间排序，再执行过滤并发送给当前渲染路径。证据：`lib/utils/video_player_state.dart:1315`；`lib/utils/video_player_state/video_player_state_danmaku.dart:633`、`:678`、`:710`。

现有过滤包括顶部/底部/滚动类型、剧透文本、用户屏蔽词及插件屏蔽词，词规则支持子串和约定格式的正则。证据：`lib/utils/video_player_state/video_player_state_subtitles.dart:591`、`:608`、`:624`、`:645`。

需要区分三种“合并”：

1. **轨道合并**：连接启用轨道并排序，当前没有在此处进行跨源身份去重。
2. **获取/缓存去重**：按时间、文本、类型、颜色拼接的字符串键去重。
3. **显示合并**：由具体渲染内核处理重复弹幕、堆叠和布局；原生Erika路径接收相关设置。

证据：`lib/utils/video_player_state/video_player_state_danmaku.dart:640`；`lib/services/dandanplay_service_io.dart:1774`；`lib/services/danmaku_cache_manager.dart:294`；`lib/utils/video_player_state/video_player_state_danmaku.dart:74`。

轨道偏移的实际约定是：

```text
轨道映射后的时间 = 原始时间 − trackOffset
```

**正数表示提前，负数表示延后，单位为秒。** 实现生成新的条目副本，不累积修改源时间。显示时还有全局手动偏移与弹弹play自动偏移。证据：`lib/utils/danmaku_track_timing.dart:1`、`:8`；`lib/widgets/danmaku_overlay.dart:76`；`test/danmaku_track_timing_test.dart:15`、`:36`。

现有轨道接口支持偏移、启停和删除，但拒绝删除 `dandanplay`，也拒绝给 `timeline` 设置轨道偏移。Harness包装时应显式返回冲突或不支持，不能把静默返回当作成功。证据：`lib/utils/video_player_state/video_player_state_danmaku.dart:1332`、`:1340`、`:1350`。

### 1.5 缓存及持久化缺口

`DanmakuCacheManager`提供内存和磁盘缓存，键主要为弹弹play `episodeId`；磁盘文件带元数据侧文件，磁盘操作串行化。TTL依据 `animeId`阈值选择七天或两小时；Web路径不使用此磁盘缓存。证据：`lib/services/danmaku_cache_manager.dart:19`、`:28`、`:56`、`:110`、`:157`、`:209`。

它的去重键不包含来源、平台弹幕ID或用户身份，且写入失败被捕获后不继续抛出。因此，不宜直接用作多平台无损缓存，也不能仅凭其保存方法返回就生成“已验证落盘”回执。证据：`lib/services/danmaku_cache_manager.dart:209`、`:230`、`:294`。

另外存在一条媒体资产关联的原始弹弹playJSON缓存链路：

- 刷新方法实际写入 `cache/danmaku/dandanplay/{episodeId}.json`。
- 按资产hash读取的方法实际查找 `cache/danmaku/{episodeId}.json`。
- 两处路径在当前代码中不一致。

证据：`lib/services/anime_info/api_repository.dart:99`、`:109`；`lib/services/anime_info/anime_info_service_impl.dart:258`、`:272`。这是一处代码层面的路径差异；本次没有运行验证其实际影响。

当前轨道位于播放器内存，清理播放状态时会清空。现有观看历史同步保存弹弹play作品/分集信息，没有在该同步接口中保存任意平台轨道与独立偏移。证据：`lib/utils/video_player_state/video_player_state_danmaku.dart:131`；`lib/utils/danmaku_history_sync.dart:18`、`:53`。

### 1.6 弹幕相关插件能力

| 能力 | 已核实行为 | 证据 |
|---|---|---|
| `danmaku.modify` | 显隐、透明度、过滤词、数据替换及相似度辅助API | `lib/plugins/models/plugin_permission.dart:4`；`lib/plugins/plugin_service.dart:1232` |
| 过滤事件链 | `danmakuLoaded`按插件优先级执行，后续插件接收前序修改结果 | `lib/plugins/plugin_service.dart:848` |
| 静态词库 | `pluginBlockWords`支持文本与正则规则 | `assets/plugins/README.md:22`、`:29` |
| 相似度引擎 | 提供批量分组与单对相似度；原生不可用时返回默认结果 | `lib/plugins/similarity_ffi_service_io.dart:43`、`:100` |
| `danmaku.renderer` | 声明本地WebView渲染器，接收标准化列表、设置和时钟 | `lib/plugins/models/plugin_permission.dart:5`；`assets/plugins/README.md:80` |
| 渲染器装载 | 宿主把播放器当前弹幕列表转换后发送给渲染器 | `lib/plugins/danmaku/plugin_danmaku_webview_overlay.dart:181` |
| 原生优先级 | 原生弹幕激活时不启用插件渲染器 | `lib/plugins/models/plugin_danmaku_renderer.dart:40` |

已查看的权限枚举没有 `danmaku.source`，清单模型也没有弹幕来源声明。现有弹幕插件主要是修改与渲染能力，不是完整的来源获取接口。证据：`lib/plugins/models/plugin_permission.dart:1`；`lib/plugins/models/plugin_manifest.dart:4`。

过滤链还有一个语义缺口：播放器只在 `pendingDanmakuData`非空且非空列表时接受替换，插件返回空列表不能在这些加载入口表达“全部过滤掉”。新契约应区分“没有修改”与“修改为空”。证据：`lib/utils/video_player_state/video_player_state_danmaku.dart:387`、`:471`、`:597`。

### 1.7 直接复用与新增边界

| 可复用部分 | 应新增或调整的部分 |
|---|---|
| 多轨装载、启停、排序、轨道偏移 | 强类型轨道、稳定ID、媒体绑定持久化 |
| `DanmakuItem`及旧Map转换 | 明确平台、视频ID、来源实例、覆盖范围 |
| XML/JSON解析与ASS输出 | 各平台protobuf、压缩包、嵌套JSON解码 |
| 用户/插件过滤及相似度工具 | 无损源缓存、可追溯跨源显示去重 |
| 当前渲染器与原生内核 | 来源获取不依赖渲染器 |
| JS运行时与宿主请求续传模式 | 来源注册、二进制传输、凭据引用、强制权限检查 |
| Task Engine内核 | 弹幕执行器、检查点、来源回执及应用接线 |

该拆分是提案；依据见前述多轨实现、`lib/models/danmaku/danmaku_item.dart:8`、`lib/plugins/url_resolver.dart:81`、`packages/nipa_harness/lib/src/tasks/engine.dart:5`。

---

## 2. download-harness优酷实现

### 2.1 获取分集与定位

`youku_episodes(show_id)`调用公开作品分集接口 `openapi.youku.com/v2/shows/videos.json`，请求正片，读取 `seq`、`id`、标题、时长、链接，输出分集清单。调用方必须先知道 `show_id`；模块没有作品关键词搜索。证据：`download-harness/danmaku.py:54`；`download-harness/docs/DANMAKU.md:16`。

当前固定请求第一页、一百项，虽然返回 `total`，没有继续翻页。迁移时必须加入分页和完整性检查，不能把列表长度当作整部作品集数。证据：`download-harness/danmaku.py:55`、`:74`。

### 2.2 分段与签名机制

实现要求调用方提供含 `_m_h5_tk` 的优酷浏览器登录态。每集按分钟顺序请求 `mopen.youku.danmu.list`，段索引从零开始，请求包含视频ID、当前时间、客户端信息和随机标识。证据：`download-harness/danmaku.py:77`、`:83`、`:99`。

签名包含两层机制：

1. 将请求消息紧凑序列化并Base64编码，以协议约定常量参与MD5计算。
2. 以浏览器令牌的相关部分、请求时间、应用标识和最终请求数据计算外层MD5签名。

这里仅描述机制，不列出令牌、密钥、盐值或签名结果。证据：[danmaku.py:86](~/Documents/ChatGPT/download-harness/danmaku.py:86)。

响应处理尝试接收JSON/JSONP，再解析外层 `data.result`中的JSON字符串；条目的 `playat`从毫秒转换为秒，`propertis`提供位置、字号和颜色。证据：`download-harness/danmaku.py:119`、`:124`、`:129`、`:146`。

### 2.3 输出与验证

输出是B站格式XML：根节点 `<i>`，每条弹幕为 `<d p="...">文本</d>`，时间保留两位小数，XML库负责文本转义，`chatserver`写为优酷。用户与弹幕ID位置写为零，因而没有保留真实身份和弹幕ID。证据：`download-harness/danmaku.py:155`、`:170`。

分集文件命名为 `标题 S01E{集号}.xml`。另一个独立操作把XML放到工作站匹配视频旁，并核对远端文件大小；它不属于来源获取本身，也不是时间轴正确性的验证。证据：`download-harness/danmaku.py:188`、`:200`、`:245`、`:253`。

测试文件包含三个测试，覆盖分集字段转换、XML时间/格式与文本转义、缺少登录态的失败入口；没有分段HTTP、签名有效性、令牌过期或接口变化测试。本次未运行这些测试。证据：`download-harness/tests/test_danmaku.py:9`、`:24`、`:35`。

### 2.4 对接口变化的应对与实际缺口

已实现的兼容处理包括JSON/JSONP外壳、结果列表/单对象、属性字符串/对象，以及属性解析失败时的默认值。请求错误包装为 `DanmakuError`，基础JSON请求错误消息主动去掉URL查询部分。证据：`download-harness/danmaku.py:28`、`:119`、`:126`、`:129`。

但当前实现没有明确检查弹幕响应HTTP状态和业务返回码；缺失 `data.result`会变成空结果。单段网络异常会中止整集，没有自动重试、令牌刷新、取消或持久检查点。证据：`download-harness/danmaku.py:113`、`:124`、`:150`。

这与项目文档“保留错误，不用空弹幕冒充成功”的目标存在差距。迁移时应把合法空段、登录过期、接口结构变化和传输失败拆开。证据：`download-harness/docs/DANMAKU.md:65`、`:70`。

### 2.5 迁移建议

以下均为提案：

| 迁移内容 | 处理方式 | 依据 |
|---|---|---|
| 分集字段与正片筛选 | 保留，补分页 | `download-harness/danmaku.py:54` |
| 分钟段计划与时间转换 | 保留，增加段覆盖回执 | `download-harness/danmaku.py:100`、`:146` |
| 签名消息结构 | 移到受控宿主请求配置，凭据不进入插件 | `download-harness/danmaku.py:86`；`docs/next/DESIGN.md:58` |
| 属性映射 | 保留原始值，同时输出标准模式和降级标记 | `download-harness/danmaku.py:129` |
| XML输出 | 作为兼容导出；应用内部直接使用统一模型 | `download-harness/danmaku.py:155` |
| 浏览器Cookie读取 | 不迁移到来源插件，由宿主提供授权会话引用 | `download-harness/danmaku.py:37`；`docs/next/DESIGN.md:58` |
| 工作站上传 | 保持独立，不纳入 `DanmakuSource` | `download-harness/AGENTS.md:216` |
| 错误与测试 | 加入脱敏离线样例和分段完整性验证 | `download-harness/docs/DANMAKU.md:70`；`download-harness/tests/test_danmaku.py:9` |

---

## 3. 六个平台的获取方式

以下接口说明以公开代码与资料为依据。除弹弹play外，本次没有取得可据以承诺长期兼容的官方弹幕开放API契约；“无需登录”仅表示引用实现未显式附加用户登录态，不保证所有内容和所有地区均可匿名获取。

### 3.1 B站

**剧集定位。** 普通投稿由AV/BV定位，通过 `x/web-interface/view`获取分P与 `cid`；番剧由 `season_id`或 `ep_id`查询 `pgc/view/web/season`，分集返回 `aid`、`cid`和链接。公开资料另列有 `pgc/web/season/section`。弹幕获取所需核心ID是分集 `cid`，不能只保存作品ID或BV号。证据：[KikoPlayScript B站来源](https://github.com/KikoPlayProject/KikoPlayScript/blob/master/danmu/bilibili.lua#L104)、`download-harness/docs/DANMAKU.md:34`。

**接口形态。** `x/v2/dm/web/seg.so`使用protobuf，通常每360秒一段，`oid=cid`、`segment_index`从一开始；新路径 `x/v2/dm/wbi/web/seg.so`要求WBI。`progress`为毫秒，包含模式、字号、RGB颜色、用户哈希、文本、发送时间与字符串弹幕ID。旧XML路径也有公开实现。证据：[protobuf接口资料](https://github.com/Janson20/bilibili-api-collect-mirror/blob/master/docs/danmaku/danmaku_proto.md)、[XML接口资料](https://github.com/Janson20/bilibili-api-collect-mirror/blob/master/docs/danmaku/danmaku_xml.md)。

**登录与完整性。** 公开资料标明部分视频无登录态只返回部分弹幕；历史弹幕日期查询和历史分段需要登录态。因此，“当前分段请求成功”不能等同于“取得完整历史弹幕”。证据：[protobuf接口资料](https://github.com/Janson20/bilibili-api-collect-mirror/blob/master/docs/danmaku/danmaku_proto.md)、[历史弹幕资料](https://github.com/Janson20/bilibili-api-collect-mirror/blob/master/docs/danmaku/history.md)。

**稳定性评估。** 公开资料同时存在旧、新WBI路径和历史接口变更记录，适合版本化适配。**推测：** 协议资料较完整会降低初期开发成本，但不能保证匿名覆盖或风控稳定。

已知开源项目：

- [bilibili-api-collect-mirror](https://github.com/Janson20/bilibili-api-collect-mirror)
- [KikoPlayScript](https://github.com/KikoPlayProject/KikoPlayScript)
- [danmu_api](https://github.com/huangxd-/danmu_api)

### 3.2 优酷

**剧集定位。** harness由 `show_id`查询正片清单，取得各集 `vid`与链接；公开 `danmu_api`实现另使用优酷搜索接口，并支持分集分页。证据：`download-harness/danmaku.py:54`；[YoukuSource](https://github.com/huangxd-/danmu_api/blob/main/danmu_api/sources/youku.js#L141)。

**接口形态。** `acs.youku.com/h5/mopen.youku.danmu.list/1.0/`按60秒窗口请求，返回嵌套JSON/JSONP，条目 `playat`为视频内毫秒时间。证据：`download-harness/danmaku.py:100`、`:114`、`:124`、`:146`。

**登录与签名。** harness明确要求用户浏览器令牌，采用消息层及外层签名。这里只能确认此实现的要求，不能据此证明所有优酷弹幕路径都必须用户登录。证据：`download-harness/AGENTS.md:214`；`download-harness/danmaku.py:83`、`:86`。

**稳定性评估。** 依赖有效浏览器会话、签名协议和嵌套响应。当前harness没有令牌刷新和业务错误识别，迁移前需要补齐；本次未验证应用身份参数的长期可用性。证据：`download-harness/danmaku.py:54`、`:86`、`:113`。

已知开源项目：

- [danmu_api](https://github.com/huangxd-/danmu_api)

### 3.3 爱奇艺

**剧集定位。** KikoPlayScript使用 `search.video.iqiyi.com/o`取得 `tvId`；也通过播放器元信息和 `video/video/baseinfo/{tvId}`定位。较新的 `danmu_api`使用搜索页面接口与签名的 `base_info`接口读取分集。页面短ID与数字 `tvid`需要区分。证据：[KikoPlayScript爱奇艺来源](https://github.com/KikoPlayProject/KikoPlayScript/blob/master/danmu/iqiyi.lua#L26)、[IqiyiSource](https://github.com/huangxd-/danmu_api/blob/main/danmu_api/sources/iqiyi.js#L281)。

**接口形态。** 已核实两套公开实现：

- 旧实现请求 `cmts.iqiyi.com/bullet/{分桶1}/{分桶2}/{tvid}_300_{段号}.z`，解压后解析XML，`showTime`按秒读取。分桶不是“四位目录加两位目录”：代码取倒数第四至第三位、最后两位，各两位。
- 较新实现使用60秒段、带MD5校验后缀的 `.br`路径，Brotli解压后根据内容解析XML或protobuf；`showTime`转换为秒值。

证据：[旧实现](https://github.com/KikoPlayProject/KikoPlayScript/blob/master/danmu/iqiyi.lua#L113)、[较新分段及解码实现](https://github.com/huangxd-/danmu_api/blob/main/danmu_api/sources/iqiyi.js#L997)。

**登录与签名。** 旧抓取代码未显式提供用户Cookie或签名；较新代码包含元信息签名与分段校验。不能把“旧实现匿名请求”当作永久不需要认证的契约。证据：上述来源代码。

**稳定性评估。** 已核实存在段长、压缩格式与解码结构差异。**推测：** 仅移植旧 `.z`路径会有较高兼容风险；新旧路径是否同时适用于某一集，需要实际样例验证。

已知开源项目：

- [KikoPlayScript](https://github.com/KikoPlayProject/KikoPlayScript)
- [danmu_api](https://github.com/huangxd-/danmu_api)

### 3.4 腾讯视频

**剧集定位。** 页面通常包含合集 `cid`与单集 `vid`；公开实现通过搜索接口及 `PageServer/GetPageData`取得分集 `vid`，构造播放链接。弹幕索引按单集 **`vid`** 请求。harness文档写成 `/barrage/base/<cid>`，与核实的公开代码不一致，迁移应采用单集ID。证据：[TencentSource分集实现](https://github.com/huangxd-/danmu_api/blob/main/danmu_api/sources/tencent.js#L307)、[弹幕索引实现](https://github.com/huangxd-/danmu_api/blob/main/danmu_api/sources/tencent.js#L745)、`download-harness/docs/DANMAKU.md:50`。

**接口形态。** 先请求 `dm.video.qq.com/barrage/base/{vid}`读取 `segment_index`，再按返回的 `segment_name`请求分段JSON。条目 `time_offset`为毫秒，`content_style`可描述位置和颜色。段边界应服从索引，不写死统一段长。证据：[TencentSource](https://github.com/huangxd-/danmu_api/blob/main/danmu_api/sources/tencent.js#L745)、[KikoPlayScript腾讯来源](https://github.com/KikoPlayProject/KikoPlayScript/blob/master/danmu/tencent.lua#L67)。

**登录与签名。** 核实的上述弹幕请求未显式附加用户Cookie或额外签名。受限内容、地区或风控场景是否要求登录，本次未验证。

**稳定性评估。** 搜索和分集查询依赖页面RPC及复杂分页结构；弹幕分段有索引可以减少段长猜测。**推测：** 搜索/分集适配的维护量可能高于弹幕JSON解码。依据：[TencentSource](https://github.com/huangxd-/danmu_api/blob/main/danmu_api/sources/tencent.js#L301)。

已知开源项目：

- [KikoPlayScript](https://github.com/KikoPlayProject/KikoPlayScript)
- [danmu_api](https://github.com/huangxd-/danmu_api)

### 3.5 芒果TV

**剧集定位。** 播放链接形如 `/b/{作品或合集ID}/{video_id}.html`。公开实现用搜索结果的 `clipId`查询 `pcweb.api.mgtv.com/variety/showlist`，按返回分集的 `video_id`构造链接；视频元信息用于取得时长及确认身份。证据：[MangoSource](https://github.com/huangxd-/danmu_api/blob/main/danmu_api/sources/mango.js#L81)、[KikoPlayScript芒果来源](https://github.com/KikoPlayProject/KikoPlayScript/blob/master/danmu/mgtv.lua)。

**接口形态。** 公开实现先读取 `galaxy.bz.mgtv.com/getctlbarrage`，再按返回CDN及版本请求每分钟JSON；结构不满足条件时构造 `rdbarrage`分钟段请求。条目 `time`从毫秒转换为秒。证据：[MangoSource分段实现](https://github.com/huangxd-/danmu_api/blob/main/danmu_api/sources/mango.js#L597)。

**登录与签名。** 芒果搜索实现包含设备标识和摘要式请求参数；KikoPlay播放器元信息路径生成 `tk2`。核实的弹幕请求未显式附加用户登录态，但本次未验证受限内容是否相同。证据：[MangoSource搜索](https://github.com/huangxd-/danmu_api/blob/main/danmu_api/sources/mango.js#L81)、[KikoPlayScript芒果来源](https://github.com/KikoPlayProject/KikoPlayScript/blob/master/danmu/mgtv.lua)。

**稳定性评估。** 新旧路径、CDN版本及元信息耦合均已在公开代码中出现。**推测：** 使用平台返回的控制信息比长期硬编码CDN路径更易维护。

已知开源项目：

- [KikoPlayScript](https://github.com/KikoPlayProject/KikoPlayScript)
- [danmu_api](https://github.com/huangxd-/danmu_api)

### 3.6 AcFun

**剧集定位。** 公开实现支持投稿 `ac...`与番剧 `aa...`；番剧搜索通过 `rest/pc-direct/search/bgm`取得分集链接，再从目标页面解析实际 `videoId`。网页作品ID、分集链接ID与弹幕 `resourceId`不能混用。证据：[AcFun来源定位实现](https://github.com/KikoPlayProject/KikoPlayScript/blob/master/danmu/acfun.lua#L28)。

**接口形态。** POST `rest/pc-direct/new-danmaku/list`，使用 `resourceId`、`resourceType=9`、`count`和 `pcursor`翻页，直到 `no_more`。这是游标分页，不是固定时间分段；JSON字段包括 `position`、`body`、模式、字号、颜色和发送时间，公开实现把 `position`直接用于毫秒时间轴。证据：[AcFun弹幕实现](https://github.com/KikoPlayProject/KikoPlayScript/blob/master/danmu/acfun.lua#L104)。

**登录与签名。** 核实的该实现没有显式附加用户Cookie或签名；其他资源类型、受限内容及风控条件未验证。

**稳定性评估。** 页面 `videoId`解析与分页字段是适配依赖。**推测：** 页面结构变化可能先影响定位，重复游标或中途失败可能造成不完整结果。

已知开源项目：

- [KikoPlayScript](https://github.com/KikoPlayProject/KikoPlayScript)

### 3.7 接入验证要求

以下为提案。平台上线前应按单集、小范围完成：

- URL/作品定位与分集ID核对，区分正片、预告、花絮及不同剪辑。
- 匿名与用户授权登录态的返回差异。
- HTTP成功、业务成功、合法空段及权限拒绝的区分。
- 时间单位、段号起点、跨段重复和分页终止条件。
- 单段失败、取消、重启恢复及部分覆盖。
- 地区与会员限制只记录实际结果，不通过其他身份或路径绕过。

这些验证针对已核实的接口差异；范围边界来自 `docs/next/DESIGN.md:398`、`download-harness/AGENTS.md:205`。

---

## 4. 统一模型与聚合策略

本节全部为提案。现有 `DanmakuItem`已经包含时间、文本、模式、颜色、发送者、弹幕ID、发送时间、来源、字号及扩展字段，可扩展后复用。证据：`lib/models/danmaku/danmaku_item.dart:21`、`:45`。

### 4.1 标准条目

| 字段 | 建议语义 |
|---|---|
| `itemId` | 宿主稳定ID；优先根据来源与平台弹幕ID生成 |
| `sourceId` | 注册的来源能力ID |
| `sourceInstanceId` | 本次具体视频来源实例 |
| `platform` | `bilibili`、`youku`等；未知来源明确为未知 |
| `platformVideoId` | 视频ID字符串，不与弹幕ID混用 |
| `platformDanmakuId` | 平台弹幕ID字符串；不存在时为 `null` |
| `sourceTimeMs` | 平台视频时间轴上的整数毫秒，保持原始含义 |
| `mode` | 标准模式枚举 |
| `originalMode` | 原始平台模式及必要降级信息 |
| `colorRgb` | 24位RGB整数 |
| `fontSize` | 原始字号，可为空；显示缩放另行处理 |
| `text` | 原始文本；匹配用标准化文本不覆盖原文 |
| `sentAt` | UTC发送时间，可为空；未知时区不得擅自换算 |
| `sender` | 可空身份描述：平台命名空间、身份类型、哈希或宿主处理后的值 |
| `pool`、`weight`、`likes` | 平台确实提供时保存 |
| `extra` | 有限、经过schema约束的扩展数据 |

选择整数毫秒可以直接承接B站 `progress`、优酷 `playat`、腾讯 `time_offset`，兼容旧播放器时再转换为秒。平台ID使用字符串可以避免JS对大整数的精度损失。依据：[B站protobuf字段](https://github.com/Janson20/bilibili-api-collect-mirror/blob/master/docs/danmaku/danmaku_proto.md)、`download-harness/danmaku.py:146`、[TencentSource](https://github.com/huangxd-/danmu_api/blob/main/danmu_api/sources/tencent.js#L830)。

身份必须带平台命名空间。没有可靠身份时保存 `null`，不把昵称、弹幕ID或数字零当成用户哈希，也不跨平台推断同一用户。现有代码存在从多种字段推断发送者的兼容逻辑，新来源应在进入兼容层前完成明确映射。依据：`lib/utils/danmaku_parser.dart:6`、`lib/models/danmaku/danmaku_item.dart:50`。

### 4.2 来源、绑定与轨道元信息

建议分为三层：

| 层次 | 元信息 |
|---|---|
| 来源能力 | ID、名称、平台、插件/内置版本、契约版本、运行平台、能力、网络域名、凭据需求 |
| 视频来源实例 | 平台作品/视频ID、公开规范链接、标题、季集号、时长、内容类型、定位证据、接口版本、获取时间、覆盖范围 |
| 媒体绑定/轨道 | 本地媒体或资产ID、来源实例ID、启用状态、时间映射、绑定版本、内容摘要、偏移依据 |

另保存：

- `aggregation`与来源构成是否已知；
- `coverage`，区分当前弹幕池、历史快照、平台筛选结果与未知；
- `complete`及已覆盖区间/游标；
- 原始、有效、被过滤和显示条目数；
- 缺失段与失败原因。

这是为补齐当前轨道Map和缓存仅有部分来源信息的缺口。依据：`lib/utils/video_player_state/video_player_state_danmaku.dart:373`、`:583`；`lib/services/danmaku_cache_manager.dart:216`。

### 4.3 时间轴对齐

同一集不代表同一剪辑时间轴。片头片尾长度、删减、回顾段、平台台标、广告位或播放版本都应作为定位和对齐检查项。**推测：** 某个平台广告是否改变弹幕内容时间轴，必须按实际播放器及接口样例确认，不能默认减去广告时长。

建议采用以下递进模型：

1. **固定偏移**：处理整集稳定的起点差异。
2. **分段平移**：处理局部插入、删减或片头后差异。
3. **线性缩放加平移**：仅在多个锚点支持持续比例差异时使用。
4. **明确无法对齐**：版本差异过大时保留原轨道并请求判断。

现有播放器只提供固定轨道偏移；分段映射属于新增能力。依据：`lib/utils/danmaku_track_timing.dart:8`。

可行的偏移估计方法：

| 方法 | 使用条件 | 验证方式 |
|---|---|---|
| 手动事件锚点 | 用户指出某条弹幕对应的本地画面时刻 | 保存来源时间与本地时间 |
| 同剪辑字幕锚点 | 已有合法可访问的字幕 | 多处台词匹配，检查残差 |
| 音频/画面指纹 | 用户有权访问参考媒体片段 | 多点匹配，限制读取范围 |
| 弹幕文本匹配 | 两个来源确有转存或明显重叠 | 稀有文本多点匹配，排除通用短语 |
| 弹幕密度互相关 | 作为候选估计 | 分窗口比较，并要求独立锚点确认 |
| 片头片尾标记 | 标记对应同一剪辑 | 作为候选边界，不单独证明全片对齐 |

这些方法尚未在本项目验证有效率。现有密度统计与相似度工具可用于实现候选估计，但不能直接充当“对齐已验证”的证据。依据：`lib/services/danmaku_density_analyzer.dart:15`、`lib/plugins/similarity_ffi_service_io.dart:43`。

估计结果应包括方法、锚点、残差、适用区间、置信度和确认状态。低置信度返回Decision，不自动提交。

还需处理现有全局自动偏移：它会影响全部显示轨道。新增平台对齐后，不能再无条件叠加一份只适用于弹弹play的匹配偏移。建议选择统一参考时间轴，并将来源专属校正放到各轨道；过渡阶段明确记录兼容公式，避免重复补偿。依据：`lib/widgets/danmaku_overlay.dart:76`、`lib/utils/video_player_state.dart:1812`。

### 4.4 去重与密度控制

建议把源数据和显示策略分开：

- **源内重复请求去重**：按来源实例及平台弹幕ID；无ID时使用明确版本的稳定指纹。
- **跨源转存去重**：有可靠原始ID或来源证据时建立关联。
- **显示折叠**：在对齐后的短时间窗口内，对相同或相似文本形成显示组，保留成员和计数。
- **未知重叠**：弹弹play聚合轨道与直连轨道缺少来源证据时，仅保守折叠，不删除原始缓存。

不应把同一时刻多人发送的相同文本全部视为采集重复。现有去重键无法保留这种身份差异，适合继续服务旧链路，不适合新模型的无损存储。依据：`lib/services/danmaku_cache_manager.dart:294`。

密度控制建议按时间窗口、显示模式和来源份额进行确定性采样，同时保留各来源基本份额，避免高密度平台完全挤掉其他平台。原始列表保持完整，过滤、折叠和采样分别计数。现有渲染内核继续负责碰撞和堆叠。依据：`lib/utils/video_player_state/video_player_state_danmaku.dart:74`、`:678`。

---

## 5. 插件就绪的DanmakuSource契约

本节是提案，遵循“首批应用内实现、从第一天按插件接口设计”的设计要求。依据：`docs/next/DESIGN.md:398`。

### 5.1 能力声明

来源声明建议包含：

```text
sourceId
contractVersion
implementationVersion
platform
runtimePlatforms

capabilities:
  search
  listEpisodes
  resolveUrl
  segmentedFetch
  cursorFetch
  rangeFetch
  resumableFetch
  supportedModes
  aggregation

access:
  anonymous | optionalSession | requiredSession
  allowedHosts
  requestProfiles
  credentialScopes

limits:
  concurrency
  requestBudget
  responseBytes
  decompressedBytes
  itemCount
```

能力必须如实声明。AcFun游标来源不应伪装为固定时间分段；不支持历史查询的来源不应声称完整历史覆盖。依据：[AcFun分页实现](https://github.com/KikoPlayProject/KikoPlayScript/blob/master/danmu/acfun.lua#L104)、[B站历史接口资料](https://github.com/Janson20/bilibili-api-collect-mirror/blob/master/docs/danmaku/history.md)。

### 5.2 方法边界

| 方法 | 输入 | 输出与语义 |
|---|---|---|
| `describe` | 无 | 静态能力与版本 |
| `search` | 标题、类型、年份、季信息、分页 | 作品候选，保留定位证据 |
| `listEpisodes` | 作品引用、分页 | 分集候选；区分正片、特典、预告 |
| `resolve` | 公开URL或外部ID | 明确视频引用，或歧义候选 |
| `planFetch` | 视频引用、范围、访问引用 | 有限段计划或游标计划 |
| `fetchChunk` | 计划引用、段/游标、取消信号 | 标准条目、覆盖、下一游标、警告 |
| `validate` | 计划及已取结果 | 完整性与结构检查结果 |

建议先定义纯Dart端口与可序列化schema，内置Dart来源和未来JS来源实现同一语义。播放器、主题与GUI对话框不进入来源契约。依据：`docs/next/DESIGN.md:70`、`:83`、`:84`。

段描述使用宿主保存的 `chunkRef`，而非把签名URL、Cookie或完整请求头返回Agent。时间段采用明确的半开区间；游标保持不透明。结果要区分：

```text
validEmpty
partial
complete
authenticationRequired
accessDenied
rateLimited
schemaChanged
transportFailed
```

这些是建议的来源层状态/错误，不直接扩展M1的 `FailureCode`。Harness仍使用既有错误类别映射，详细机器信息放在声明过schema的任务回执或来源结果中。依据：`docs/next/DESIGN.md:248`。

### 5.3 凭据引用与宿主请求

凭据只由宿主管理，来源和Agent持有不透明 `credentialRef`或 `sessionRef`。绑定范围包括平台、用户会话、来源版本及获准域名。插件不得读取浏览器数据库或配置文件。依据：`docs/next/DESIGN.md:50`、`:58`。

对优酷这种需要令牌参与签名的协议，仅注入Cookie请求头不够。建议采用：

- 宿主执行受控签名配置；
- 插件提交经过schema验证的业务参数；
- 宿主读取令牌、生成签名、发送请求；
- 插件只获得必要响应，响应头中的会话材料被过滤。

签名能力不能变成任意数据签名或任意带凭据HTTP代理。跨域重定向需重新校验授权范围，日志只记录接口类别、脱敏视频引用、状态和耗时。依据：`download-harness/danmaku.py:86`；`docs/next/DESIGN.md:55`。

用户会话过期、验证码、权限拒绝或付费限制应停止相应获取；宿主可引导用户在自己的浏览器完成正常登录，再恢复任务。不得自动切换身份或尝试绕过限制。依据：`docs/next/DESIGN.md:398`；`download-harness/AGENTS.md:219`。

### 5.4 限流、缓存与取消

建议由宿主统一执行：

- 按平台和会话限制并发，同一来源实例的并发请求合并。
- 对超时与可重试服务错误有限退避；尊重服务返回的限流信息。
- 登录失败与结构变化不进入无限重试。
- XML、protobuf和压缩响应均限制原始大小、解压大小与条目数。
- 缓存键至少包含来源ID、视频ID、接口/解码版本、段或游标、访问范围和内容选项。
- 签名URL与令牌不持久化；恢复时重新生成请求。
- 原始来源时间缓存与媒体对齐映射分开，修改偏移不重新获取。
- 取消时停止后续调度，终止可终止的请求，并记录已完成覆盖。

现有缓存只按弹弹play分集建键；现有加载流程通过播放路径和代次检查丢弃过时结果，但不等于请求已取消。新契约需要区分“取消已受理”与“执行已停止”。依据：`lib/services/danmaku_cache_manager.dart:110`；`lib/utils/video_player_state/video_player_state_danmaku.dart:302`；`packages/nipa_harness/lib/src/tasks/actions.dart:47`。

### 5.5 与现有JS运行时的关系

现有JS端口只有同步求值、销毁和桥接；非Web使用 `flutter_js`，OHOS有专用适配，Web适配明确不支持。来源不能直接假设有浏览器环境、原生 `fetch`或protobuf库。证据：`lib/plugins/js_runtime_types.dart:1`、`lib/plugins/js_runtime_io.dart:7`、`:26`、`lib/plugins/js_runtime_web.dart:3`。

可复用 `PluginUrlResolver`的宿主驱动续传模式：

```text
脚本返回请求描述
→ 宿主异步执行IO
→ 宿主把响应与续传状态交回脚本
→ 脚本继续解析
```

当前解析器已经采用此模式，但仅支持GET、UTF-8文本响应，限制4MiB，且有步骤上限。来源适配需增加POST、二进制/受限Base64或缓冲区引用、压缩解码、进度和凭据引用。证据：`lib/plugins/url_resolver.dart:81`、`:105`、`:166`。

来源插件权限建议新增 `danmaku.source`，并与 `danmaku.modify`、`danmaku.renderer`分开：获取来源不应默认拥有播放器修改或渲染能力。网络与凭据范围由宿主强制检查。依据：现有权限枚举，`lib/plugins/models/plugin_permission.dart:1`。

这里有一项必须先处理的现状：现有弹幕权限检查主要位于注入的JS包装函数；宿主弹幕桥接分支没有逐项执行同等权限检查，且桥接允许依据消息中的 `__pluginId`重新选择插件身份。不能将这套桥接直接视为承载浏览器登录态的隔离边界。证据：`lib/plugins/plugin_service.dart:453`、`:463`、`:508`、`:1232`。

**提案：** 来源桥接使用宿主绑定的执行身份与授权记录，校验操作、域名、凭据范围和来源实例；不接受脚本自报身份作为授权依据。

### 5.6 与Harness Action的关系

建议调用链为：

```text
GUI / Agent
  → Harness Action
  → 来源注册表 / 聚合协调器
  → 内置Dart来源或JS来源适配器
  → 宿主网络、凭据和缓存
  → 标准弹幕与覆盖回执
  → 媒体绑定
  → 现有播放器多轨
```

来源负责平台协议；Action负责输入校验、effect、决策、任务和提交语义。插件不自行注册任意工具或绕过Harness修改媒体绑定。依据：`docs/next/DESIGN.md:17`、`:25`、`:52`、`:78`。

未来Agent生成来源能力时，采用设计文档的“校验、审批、注册、回滚”流程，并验证离线样例、权限清单与访问范围。首批内置实现也使用相同契约，避免日后重写。依据：`docs/next/DESIGN.md:402`。

---

## 6. 建议的Action目录与Task Engine任务

### 6.1 Action目录

以下均为新增提案，effect沿用设计文档的副作用分类。依据：`docs/next/DESIGN.md:38`。

| Action | Effect | 语义 |
|---|---|---|
| `danmaku.sources` | `read` | 列出来源、版本、能力与已知会话可用状态；不安装、不登录、不触发抓取 |
| `danmaku.search` | `read` | 有限搜索，返回带证据的作品候选，不自动绑定 |
| `danmaku.episodes` | `read` | 返回指定作品的有限分集清单及分页信息 |
| `danmaku.resolve` | `read` | 把公开URL或外部ID解析为视频引用，保留歧义 |
| `danmaku.fetch` | `write` | 创建获取与缓存任务，立即返回Job；不修改当前轨道 |
| `danmaku.attach` | `write` | 将明确来源绑定到指定媒体，必要时创建获取任务；验证后提交轨道 |
| `danmaku.tracks` | `read` | 查询媒体绑定和当前播放轨道，区分持久绑定、加载状态及覆盖 |
| `danmaku.set_enabled` | `write` | 设置明确轨道启用状态，可恢复 |
| `danmaku.detach` | `write` | 解除媒体绑定及播放轨道，保留可复用来源缓存 |
| `danmaku.offset` | `write` | 设置轨道绝对偏移毫秒值；正数提前，零重置 |
| `danmaku.align` | `write` | 创建对齐估计任务，默认只保存候选；应用映射需明确选择 |
| `danmaku.export` | `write` | 导出到授权范围内的目标；指定原始或显示结果 |
| `danmaku.cache_delete` | `destructive` | 删除明确缓存对象，与解除绑定分开 |

`fetch`归为 `write`，因为会创建持久任务和缓存；查询类Action不创建持久绑定或任务。如果搜索结果要持久保存，应另由缓存写入操作负责，避免把有副作用的行为藏在 `read`中。依据：`docs/next/DESIGN.md:42`。

`offset`应使用绝对设置而非累计加减，避免重试造成二次偏移；查询通过 `tracks`返回。沿用现有正负号，输入单位换成整数毫秒，适配时转换为秒。依据：`lib/utils/danmaku_track_timing.dart:1`。

`detach`遇到当前不可删除的弹弹play轨道，应明确返回冲突或执行已约定的禁用策略；若要支持可恢复解绑，需调整当前保护逻辑并保存恢复信息。依据：`lib/utils/video_player_state/video_player_state_danmaku.dart:1350`。

### 6.2 “给这集加上B站和优酷弹幕”的执行语义

建议流程：

1. 读取当前媒体身份、播放会话与已有轨道。
2. 优先复用已有平台外部ID，否则有限搜索作品并查询分集。
3. 核对年份、季、集标题、正片类型和时长。
4. 形成明确来源选择；歧义返回结构化Decision。
5. 获取并缓存各来源，验证结构与覆盖。
6. 估计或确认对齐，按来源保存映射。
7. 校验媒体/会话版本后提交轨道。
8. 回执分别报告两个来源的获取、覆盖、对齐和加载状态。

Action中的Decision选项必须携带可执行的后续ActionCall，符合现有 `NeedsDecision`设计；GUI与Agent走同一流程。依据：`docs/next/DESIGN.md:29`、`:227`。

两个来源中一个失败时，不能把整个请求描述为“全部完成”。可保留已成功来源，但回执必须明确部分成功、失败来源及下一步；是否要求全部来源成功才提交，应成为显式输入策略。

### 6.3 Agent判断边界

| 情况 | 建议处理 |
|---|---|
| 已有明确平台视频ID及同一剪辑证据 | 确定性程序执行 |
| 同名作品、重制版、不同年份或季度 | Agent结合证据判断；仍有歧义时交给用户 |
| 正片、预告、花絮、合集混杂 | 规则先筛选，歧义返回Decision |
| 集号不一致、特别篇插入 | Agent解释集标题与外部映射，不能仅按数组位置 |
| 不同剪辑、疑似错集 | 请求选择正确版本，不用大偏移掩盖错配 |
| 低置信度时间对齐 | 返回候选映射及锚点，等待判断 |
| 登录过期、验证码、付费或地区拒绝 | 宿主处理用户正常访问路径，任务暂停或失败 |
| 分段重试、缓存命中、排序与格式转换 | 确定性执行，不逐段唤醒Agent |

以上为提案，依据平台定位差异及 `docs/next/DESIGN.md:35`、`:396`。

### 6.4 适合Task Engine的任务

当前仓库已经存在Task Engine内核、检查点、取消信号、Decision、重试和回执类型；`task.list/get/wait/cancel`也有实现。已查看的 `NextRuntime`组合根尚未注册TaskCapability或弹幕Capability。证据：`packages/nipa_harness/lib/src/tasks/engine.dart:5`、`:11`；`packages/nipa_harness/lib/src/tasks/actions.dart:3`；`lib/next/next_runtime.dart:38`。

| 任务类型 | 建议阶段 | 检查点 |
|---|---|---|
| `danmaku.fetch` | 计划、获取、解码、验证、缓存 | 已完成段/游标、摘要、覆盖、接口版本 |
| `danmaku.attach` | 定位、待决、获取、对齐、提交、回读 | 来源选择、媒体版本、绑定ID、提交状态 |
| `danmaku.align` | 提取锚点、估计、验证、待决 | 锚点、候选映射、残差 |
| 用户限定范围的补齐任务 | 枚举授权分集、逐集处理、汇总 | 已完成分集和失败项 |

来源目录、轨道查询、单次偏移和启停通常不需要持久任务。有限搜索可直接返回；复杂跨平台定位可成为任务阶段。

任务回执建议包含：

```text
媒体ID及绑定版本
来源、平台视频ID、实现版本
约定覆盖与实际覆盖
原始/有效/过滤/显示条目数
缺失段、失败原因、重试次数
缓存摘要及回读结果
时间映射、锚点与确认状态
持久绑定结果
当前播放会话加载结果
取消时机及已提交副作用
```

`succeeded`必须表示约定验证已经完成。某来源“平台当前返回集已完整获取”也不能表述为“完整历史弹幕已取得”。现有Job模型要求成功回执达到 `verified`，因此应为合法空结果和部分覆盖定义可验证的目标。依据：`packages/nipa_harness/lib/src/tasks/model.dart:79`、`:133`；`docs/next/M2_TASKBOOK.md:46`。

播放器提交需要媒体/会话版本检查。任务运行期间用户换集时，可完成原媒体缓存与绑定，但不得把弹幕装载到新媒体；回执区分持久绑定成功与当前会话未加载。现有播放器已有路径/代次检查，可扩展复用。依据：`lib/utils/video_player_state/video_player_state_danmaku.dart:302`。

---

## 7. 实施顺序与风险

### 7.1 实施顺序

以下为建议顺序，不表示已经完成。

| 阶段 | 工作 | 验收重点 |
|---|---|---|
| 1. 模型与播放器端口 | 定义条目、来源实例、绑定、覆盖与偏移；包装现有多轨 | 来源不丢失；偏移不累积；切集不误提交 |
| 2. 缓存统一 | 新来源缓存命名空间；梳理两条弹弹play缓存链路 | 回读可验证；不跨平台撞键；旧缓存不破坏 |
| 3. 既有来源适配 | 弹弹play与本地XML/JSON实现统一契约 | Classic行为保持；聚合来源与文件格式分开 |
| 4. B站与优酷 | B站定位/protobuf；优酷迁移及宿主会话请求 | 分页、合法空段、业务失败、登录过期、覆盖 |
| 5. Harness与任务 | 新增Action及获取/绑定执行器 | 可取消、恢复、Decision继续及准确回执 |
| 6. 聚合策略 | 对齐、保守去重、来源份额、密度控制 | 原始数据无损；结果可解释；性能可接受 |
| 7. 其余平台 | 腾讯、AcFun、爱奇艺、芒果逐个平台验证 | 每个接口版本都有脱敏样例和独立开关 |
| 8. JS来源插件 | 注册、二进制桥接、权限与凭据隔离 | 不依赖渲染插件；与内置来源契约一致 |
| 9. Agent生成能力 | 接入验证、审批、注册、回滚 | 可定位版本故障，更新失败可回退 |

这一顺序先复用现有轨道，再补获取层和持久任务，符合 `docs/next/DESIGN.md:398`、`:402`。B站与优酷优先是工程建议，依据为已有协议资料及harness实现，不能解释为已证明它们最稳定。

### 7.2 主要风险与应对

| 风险 | 已核实依据 | 建议应对 |
|---|---|---|
| 聚合后重复 | 已开启related且统一来源标记 | 将弹弹play声明为聚合源，保守显示折叠 |
| 来源误标 | XML解析固定标为B站 | 格式与平台分离 |
| 多来源绑定丢失 | 当前轨道在播放器内存中清空 | 持久化媒体绑定，播放时重建轨道 |
| 缓存污染与假验证 | 旧键仅基于分集；保存失败被吞掉 | 新缓存命名空间及回读验证 |
| 缓存路径不一致 | 原始JSON读写路径不同 | 实施前明确统一入口及迁移规则 |
| 空结果冒充成功 | harness缺失结果字段默认为空 | 校验HTTP、业务码与schema |
| 接口升级 | B站WBI、爱奇艺新压缩路径、芒果新旧路径 | 版本化适配、离线样例和局部停用 |
| 大整数与身份混用 | JS边界及既有兼容字段推断 | ID字符串化，区分视频/弹幕/用户ID |
| 凭据暴露 | 优酷签名需要会话；现有桥接未形成强隔离 | 宿主签名、范围校验、响应脱敏 |
| 对齐误判 | 现有仅固定偏移，自动偏移为全局 | 多锚点验证，低置信度Decision |
| 取消后继续副作用 | 逻辑失效不等于网络取消 | 取消信号、检查点及提交回读 |
| 多轨性能 | 当前合并重排并重新加载列表 | 分段批量提交，测试热点段及大列表 |
| 开源代码许可 | 参考项目存在独立许可证 | 移植前核对许可证及依赖，不把可访问等同于可任意复制 |

证据对应：`lib/services/dandanplay_service_io.dart:1671`、`:1745`；`lib/utils/danmaku_xml_utils.dart:137`；`lib/utils/video_player_state/video_player_state_danmaku.dart:131`、`:633`；`lib/services/danmaku_cache_manager.dart:110`、`:230`；`lib/services/anime_info/api_repository.dart:109`；`lib/services/anime_info/anime_info_service_impl.dart:272`；`download-harness/danmaku.py:124`；`lib/plugins/plugin_service.dart:453`；[danmu_api许可证](https://github.com/huangxd-/danmu_api/blob/main/LICENSE)。

平台使用范围同样需要按实际接入核对。弹弹play官方要求按需调用与缓存，禁止规模化抓取，并已引入应用额度管理；来源任务应受用户指定媒体范围与请求预算约束。证据：[弹弹play官方使用约定](https://doc.dandanplay.com/open/#_9-第三方开发者接入-api-的使用约定)、`download-harness/AGENTS.md:219`。

### 7.3 首批完成标准

首批完成不以“偶尔抓到弹幕”为标准，建议至少证明：

- 给明确的一集附加B站与优酷来源后，各自拥有可查询、启停、调整和解除的轨道。
- 轨道、缓存及回执保留真实来源，XML格式不会改变平台身份。
- 任何失败来源、缺失段和低置信度对齐都可见，不以空结果掩盖。
- 用户换集、取消或重启后，任务与绑定结果保持正确。
- 插件和Agent只能使用宿主授予的会话引用，不能读取或收到原始凭据。
- 原始来源数据可追溯，显示去重与密度控制可以关闭。
- Classic和Agent使用同一业务实现，并回读验证最终结果。

这些是提案验收项，直接对应现有多轨机制、harness实现缺口及Next的Action、Decision和验证回执设计。依据：`lib/utils/video_player_state/video_player_state_danmaku.dart:522`、`:1328`；`download-harness/docs/DANMAKU.md:70`；`docs/next/DESIGN.md:8`、`:29`、`:58`；`docs/next/M2_TASKBOOK.md:48`。