# X20：远程媒体事实查询

日期：2026-10-11。worktree：`~/Desktop/nipaplay-next-wt/remote-meta`；分支：`next/remote-meta`。

## 1. 完成了什么

`media.sources.browse` 现在在条目的 `metadata` 中提供 Jellyfin / Emby 已有的标题、剧名、季名、季集编号、年份、原名、简介、服务器路径、容器、时长、ProviderIds、全部返回的媒体版本及媒体流。服务器没有提供的字段不补写；空 ProviderIds 保留为空对象。轨道的语言、编码、索引、默认/外部/强制标记，以及服务器返回的其他媒体流属性都会提供。

每个条目附带 `provenance`：sourceId、服务器类型、配置名称、地址、远程条目 ID、UTC 查询完成时间。这个来源说明适用于 `metadata` 和服务器描述字段；`fileId` 是宿主索引产生的 ID，`path` 是原有 Classic 播放定位符，真正的服务器文件路径单列为 `metadata.Path`。

新增只读能力 `media.sources.query`，输入 `{sourceId, itemIds}`，支持批量查询 Jellyfin / Emby 的任意条目（包括剧与季），以及 SMB / WebDAV 的目录条目。返回同一事实结构、total 和 missingItemIds。查询不注册文件，fileId 为 null，不创建身份、绑定或观看记录。Agent 可以一次浏览全部剧集，再把所需的 seriesId / seasonId 合并成一次查询；父级平台编号不被当作集编号。

SMB / WebDAV 提供 Path、Size（字节）、LastModified（UTC ISO 8601）及来源。SMB 的原有客户端丢掉了修改时间，本次只新增可选事实字段：libsmb2 目录 JSON 携带 mtime，FFI 与 Dart 客户端传递到查询层。Classic 的现有请求默认参数、播放定位符、持久身份和绑定代码未改。没有新增依赖、commit 或 push。

相关文件：

- `lib/next/media_sources/capability.dart`：能力与可发现的字段 schema。
- `lib/next/media_sources/service.dart`、`metadata.dart`：批量读取与事实输出。
- `lib/services/media_server_service_base.dart`：原目录客户端增加可选 Fields / Ids 参数，原默认请求保持原样。
- `lib/services/smb_service.dart`、`smb2_native_service_ffi.dart`、`packages/nipaplay_smb2/src/nipaplay_smb2.c`：修改时间透传。
- `test/next/media_sources_test.dart`：来源与身份数据约束。
- `test/next/remote_metadata_real_experiment_test.dart`：真实服务器实验入口。

## 2. 决策

1. 保留服务器原生字段名和值，不规范化 ProviderIds 的大小写、厂商名称或编号，也不从文件名、简介或父条目推断身份。RunTimeTicks 保持服务器的 100 纳秒单位；多媒体版本分别保留，不替 Agent 挑选版本或轨道。
2. 复用 Classic 的认证、地址选择、HTTP 客户端和完整分页。浏览只增加请求字段，没有逐集补发详情请求，也没有调用外部识别平台或读取媒体文件。批量条目查询按最多 100 个 ID 分组，再使用原分页客户端，避免无限增长的查询 URL；不对条目类型加过滤，因此可以查询父级剧与季。
3. 服务器资料只作为实时查询结果返回，不持久化新事实、迁移索引或修改绑定。浏览沿用此前的文件注册行为，查询不注册文件，方便另一组接入身份绑定。
4. 输出保留识别和技术事实，排除 MediaSources 的播放 URL / RequiredHttpHeaders，以及媒体流的 DeliveryUrl / ExternalUrl；最终结果继续经过现有 SecretRedactor。这些地址和头可能携带会话秘密，轨道事实本身保留。
5. 文件源批量查询按父目录分组，每个目录只读取一次。文件名中的逗号合法；逗号约束仅用于 Jellyfin / Emby 的 Ids 参数。目录越界校验作用于原始路径片段，支持原始中文和已有百分号编码，拒绝普通或编码的 `..`，不先让 URI 规范化吞掉越界片段。
6. 使用 Flutter 测试进程调用真实 Action，不启动真实应用或窗口。偏好全部 mock、保险库为 MemoryVault、SQLite 位于临时目录，结束删除。测试 HttpClient 强制 DIRECT；原生 SMB 库从本 worktree 的 C 源码单独构建。

## 3. 实验

### 真实 Jellyfin / Emby / SMB / WebDAV

连接信息只从 `/tmp/nipa-next/testservers.json` 读取，没有输出密码或令牌。Jellyfin 为 `http://127.0.0.1:8096`，Emby 为 `http://127.0.0.1:8097`。使用 Classic acceptSession 将测试会话放入内存保险库，再经 Harness 调用 libraries、browse、query。没有修改服务器条目或替服务器匹配平台编号。

Jellyfin 和 Emby 的「番剧」各发现六集。逐集批量 query 得到与 browse 相同的 metadata，missingItemIds 为空；查询前后 media_locations 完全相同，media_bindings 为空。SMB / WebDAV 的 `/anime/` 各返回八个条目，其中六个视频、两个目录；六个视频均有大小和修改时间，单条批量查询也成功。

**这份真实样本有明确限制：两个服务器的六集 ProviderIds 全部为 `{}`，并未返回 ProductionYear、OriginalTitle 或 SeriesName。** Jellyfin 还返回空 SeriesId / SeasonId 与 “Season Unknown”；Emby 返回 ParentIndexNumber=1。直接读取服务器原始 Items 和单条详情也观察到这些缺项。本次证明实际存在的资料可以到达 Agent，不能声称从这批原始条目取得了非空 TMDB / TVDB / AniDB / IMDb 编号、年份或原名。没有把简介中的“2022”、文件名的 CHT 或父级概念补成服务器事实。

下面的表和 JSON 是真实 Action 返回值的字段摘录，未填补缺失字段。完整 browse / query 输出在 `/tmp/nipa-next/x20-observations.json`，控制台输出在 `/tmp/nipa-next/x20-real.log`。

| 来源 | 条目 ID | 集号 | 季号 | RunTimeTicks | ProviderIds |
|---|---|---:|---|---:|---|
| jellyfin | `27ecb73cfb8fab575186e08e6fbdd58e` | 1 | null | 1400358670 | `{}` |
| jellyfin | `82ed26abf469710c7b92e1f6e4bda55e` | 2 | null | 2000124559 | `{}` |
| jellyfin | `2ce0c5b5a0b373a0b678d89fdc3ca304` | 3 | null | 2150274560 | `{}` |
| jellyfin | `fee0304c43efe74c18d7b2912c8d2e32` | 4 | null | 2500207440 | `{}` |
| jellyfin | `4701a0cb07e27035475a4a7902462dde` | 5 | null | 2000124559 | `{}` |
| jellyfin | `6b7ab63d0a66ee672287eec51671812e` | 6 | null | 3200073220 | `{}` |
| emby | `14` | 1 | 1 | 1400320000 | `{}` |
| emby | `15` | 2 | 1 | 2000000000 | `{}` |
| emby | `16` | 3 | 1 | 2150190000 | `{}` |
| emby | `12` | 4 | 1 | 2500060000 | `{}` |
| emby | `13` | 5 | 1 | 2000000000 | `{}` |
| emby | `11` | 6 | 1 | 3200000000 | `{}` |

Jellyfin 第一集：

```json
{
  "path": "jellyfin://27ecb73cfb8fab575186e08e6fbdd58e",
  "metadata": {
    "Name": "Lycoris Recoil 莉可麗絲：友誼是時間的竊賊",
    "SeasonName": "Season Unknown",
    "IndexNumber": 1,
    "Overview": " 2022年夏天播出的電視動畫《Lycoris Recoil 莉可麗絲》，這次帶著總共6篇的原創短片回來了！在LycoReco咖啡廳這個舞台上，成員們有了更多新的互動。請盡情享受非常日常的景象吧。 ＜STAFF＞ ｜原作：Spider Lily ｜導演監督：足立慎吾 ｜角色設計：伊右群 ｜配角設計：山本由美子 ｜各話嘉賓角色設計：齋藤悠、秋谷有紀惠 ｜作畫監督：山本由美子、森田莉奈、齋藤悠、合田浩章、秋谷有紀惠 ｜槍械監修：江間一隆 ｜道具設計：朱原達娜 ｜色彩設計：佐佐木梓 ｜美術監督：岡本綾乃 ｜美術設定：六七質、平義樹彌 ｜攝影監督：青嶋俊明 ｜CG監督：森岡俊宇 ｜剪輯：須藤瞳 ｜音響",
    "Path": "/anime/莉可丽丝/[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 01 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
    "Container": "mov,mp4,m4a,3gp,3g2,mj2",
    "RunTimeTicks": 1400358670,
    "ProviderIds": {},
    "MediaSources": [
      {
        "Id": "27ecb73cfb8fab575186e08e6fbdd58e",
        "Path": "/anime/莉可丽丝/[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 01 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
        "Container": "mp4",
        "Size": 24689695,
        "RunTimeTicks": 1400358670,
        "DefaultAudioStreamIndex": 1
      }
    ],
    "MediaStreams": [
      {
        "Type": "Video",
        "Index": 0,
        "Codec": "h264",
        "Language": "und",
        "Width": 1920,
        "Height": 1080,
        "IsDefault": true,
        "IsExternal": false,
        "IsForced": false,
        "DisplayTitle": "1080p H264 SDR"
      },
      {
        "Type": "Audio",
        "Index": 1,
        "Codec": "aac",
        "Language": "jpn",
        "Channels": 2,
        "SampleRate": 48000,
        "IsDefault": true,
        "IsExternal": false,
        "IsForced": false,
        "DisplayTitle": "Japanese - AAC - Stereo - Default"
      },
      {
        "Type": "EmbeddedImage",
        "Index": 2,
        "Codec": "mjpeg",
        "Width": 1200,
        "Height": 800,
        "IsDefault": false,
        "IsExternal": false,
        "IsForced": false
      }
    ]
  },
  "provenance": {
    "sourceId": "jellyfin:1791716712074",
    "type": "jellyfin",
    "name": "X20 jellyfin",
    "url": "http://127.0.0.1:8096",
    "itemId": "27ecb73cfb8fab575186e08e6fbdd58e",
    "observedAt": "2026-10-11T11:05:12.147443Z"
  }
}
```

Emby 第一集：

```json
{
  "path": "emby://14",
  "metadata": {
    "Name": "[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 01 [1080P][Baha][WEB-DL][AAC AVC][CHT]",
    "IndexNumber": 1,
    "ParentIndexNumber": 1,
    "Overview": " 2022年夏天播出的電視動畫《Lycoris Recoil 莉可麗絲》，這次帶著總共6篇的原創短片回來了！在LycoReco咖啡廳這個舞台上，成員們有了更多新的互動。請盡情享受非常日常的景象吧。 ＜STAFF＞ ｜原作：Spider Lily ｜導演監督：足立慎吾 ｜角色設計：伊右群 ｜配角設計：山本由美子 ｜各話嘉賓角色設計：齋藤悠、秋谷有紀惠 ｜作畫監督：山本由美子、森田莉奈、齋藤悠、合田浩章、秋谷有紀惠 ｜槍械監修：江間一隆 ｜道具設計：朱原達娜 ｜色彩設計：佐佐木梓 ｜美術監督：岡本綾乃 ｜美術設定：六七質、平義樹彌 ｜攝影監督：青嶋俊明 ｜CG監督：森岡俊宇 ｜剪輯：須藤瞳 ｜音響",
    "Path": "/anime/莉可丽丝/[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 01 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
    "Container": "mp4",
    "Size": 24689695,
    "RunTimeTicks": 1400320000,
    "ProviderIds": {},
    "MediaSources": [
      {
        "Id": "mediasource_14",
        "Path": "/anime/莉可丽丝/[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 01 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
        "Container": "mp4",
        "Size": 24689695,
        "RunTimeTicks": 1400320000,
        "DefaultAudioStreamIndex": 1
      }
    ],
    "MediaStreams": [
      {
        "Type": "Video",
        "Index": 0,
        "Codec": "h264",
        "Language": "und",
        "Width": 1920,
        "Height": 1080,
        "IsDefault": true,
        "IsExternal": false,
        "IsForced": false,
        "DisplayTitle": "1080p H264"
      },
      {
        "Type": "Audio",
        "Index": 1,
        "Codec": "aac",
        "Language": "jpn",
        "Channels": 2,
        "SampleRate": 48000,
        "IsDefault": true,
        "IsExternal": false,
        "IsForced": false,
        "DisplayTitle": "Japanese AAC stereo (Default)"
      },
      {
        "Type": "EmbeddedImage",
        "Index": 2,
        "Codec": "mjpeg",
        "Width": 1200,
        "Height": 800,
        "IsDefault": false,
        "IsExternal": false,
        "IsForced": false
      }
    ]
  },
  "provenance": {
    "sourceId": "emby:1791716712194",
    "type": "emby",
    "name": "X20 emby",
    "url": "http://127.0.0.1:8097",
    "itemId": "14",
    "observedAt": "2026-10-11T11:05:12.212505Z"
  }
}
```

两个服务器都报告 Video / Audio / EmbeddedImage 三个流，音轨为日语 AAC 双声道，没有报告独立 Subtitle 流。没有根据文件名的 CHT 标签推断字幕轨。

WebDAV 的一个完整文件条目：

```json
{
  "id": "/anime/[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 06 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
  "name": "[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 06 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
  "kind": "File",
  "isDirectory": false,
  "size": 94107825,
  "metadata": {
    "Path": "/anime/[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 06 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
    "Size": 94107825,
    "LastModified": "2025-05-25T14:39:59.000Z"
  },
  "path": "webdav://e1719d68-1dff-4b46-afe5-0e954dcdf341/anime/[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 06 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
  "provenance": {
    "sourceId": "webdav:e1719d68-1dff-4b46-afe5-0e954dcdf341",
    "type": "webdav",
    "name": "X20 webdav",
    "url": "http://127.0.0.1:8098/",
    "itemId": "/anime/[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 06 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
    "observedAt": "2026-10-11T11:05:12.318789Z"
  },
  "fileId": "file-8e77be89-3896-4f34-bb9f-b9ae8d31c769"
}
```

SMB 的一个完整文件条目：

```json
{
  "id": "/anime/[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 03 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
  "name": "[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 03 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
  "kind": "File",
  "isDirectory": false,
  "size": 44734175,
  "metadata": {
    "Path": "/anime/[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 03 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
    "Size": 44734175,
    "LastModified": "2025-05-25T14:38:06.000Z"
  },
  "path": "smb://d7ee798b-d87d-498e-92fd-2bbc1aae2077/anime/[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 03 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
  "provenance": {
    "sourceId": "smb:d7ee798b-d87d-498e-92fd-2bbc1aae2077",
    "type": "smb",
    "name": "X20 smb",
    "url": "smb://127.0.0.1:1445",
    "itemId": "/anime/[ANi] Lycoris Recoil 莉可麗絲：友誼是時間的竊賊 - 03 [1080P][Baha][WEB-DL][AAC AVC][CHT].mp4",
    "observedAt": "2026-10-11T11:05:12.364401Z"
  },
  "fileId": "file-f703185e-7250-4d69-adc3-dca20051b54e"
}
```

真实实验的关键控制台输出：

```text
X20 jellyfin query: total=6, missing=[], indexUnchanged=true, bindings=0
X20 emby query: total=6, missing=[], indexUnchanged=true, bindings=0
X20 output contains no supplied password/token; all stores and preferences isolated
00:00 +1: All tests passed!
```

### 非空平台编号与字幕的数据约束

原始真实样本缺少非空编号和独立字幕，所以另用独立回环 HTTP fixture 提供明确标记的模拟服务器资料，通过同一 Classic 客户端与 Action 检查透传。这不是 Jellyfin / Emby 自动匹配结果，也没有修改原始测试服务器。实际控制台输出：

```text
X20 controlled loopback fixture (not server-recognized IDs): {"ProviderIds":{"Tmdb":"123","TVDB":"456","AniDB":"789","Imdb":"tt0123","CustomProvider":"leave-this-verbatim"},"OriginalTitle":"Server original title","ProductionYear":2022,"SeriesName":"Server series title","MediaStreams":[{"Type":"Subtitle","Index":5,"Codec":"ass","Language":"chi","IsExternal":true,"IsForced":false}],"queryCreatedFiles":0,"bindings":0}
```

断言同时检查原名、年份、剧名、时长、音轨、字幕和未知 ProviderIds 键原样保留；播放 URL / 授权头中的 transport-secret 不出现；query 不写文件；browse 注册文件但修订仍为 0，media_bindings / media_external_objects 均为空。另一个目录约束检查原始中文、带逗号文件名、大小与修改时间，并确认普通或编码的越界路径在发请求前失败。

### 验证与复现

- `flutter test --no-pub test/next/media_sources_test.dart`：11 项通过。
- Classic 服务基类、目录分页与分页集成，连同来源约束：30 项通过，输出 `/tmp/nipa-next/x20-final-regression.log`。
- 初轮 Jellyfin 授权、Emby 用户媒体库、播放定位工具与来源回归：24 项通过，输出 `/tmp/nipa-next/x20-regression.log`。
- `flutter analyze --no-pub lib/next/media_sources`：No issues found。连同修改的 Classic 客户端检查，无 error / warning；原有 print、FFI 命名等 30 条 info 保留，见 `/tmp/nipa-next/x20-analyze.log`。实验脚本的 print 产生 5 条 info。
- 本 worktree 的 SMB 原生 C 构建通过，并由真实 SMB 浏览实际加载；见 `/tmp/nipa-next/x20-native-build.log`。
- `git diff --check` 通过。未运行 pub get，没有构建或启动主仓库应用，没有访问用户钥匙串或真实资料目录。

复现真实实验（工作目录必须为本 worktree；无需启动应用）：

```sh
cmake -S packages/nipaplay_smb2/src -B /tmp/nipa-next/x20-native-build -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/nipa-next/x20-native-build -j 4
mkdir -p /tmp/nipa-next/x20-native-build/nipaplay_smb2.framework
ln -sfn ../libnipaplay_smb2.dylib /tmp/nipa-next/x20-native-build/nipaplay_smb2.framework/nipaplay_smb2
ln -s /tmp/nipa-next/x20-native-build/libnipaplay_smb2.dylib libnipaplay_smb2.so
DYLD_FRAMEWORK_PATH=/tmp/nipa-next/x20-native-build \
  ~/development/flutter-3.44.6/bin/flutter test --no-pub --dart-define=NIPA_X20_REAL=true test/next/remote_metadata_real_experiment_test.dart
rm libnipaplay_smb2.so
```

framework 链接供 macOS 测试主 isolate 使用，so 链接供原生 worker isolate 使用；链接目标是本 worktree 编译的 arm64 库。实验后已删除 worktree 的临时 so 链接，临时数据库也由 teardown 删除。

### 意外与失败

- 起初按服务器内部的 `/anime/莉可丽丝/` 作为文件源入口，遇到原始中文路径的百分号解码错误；文件源实际暴露的是 `/anime/`。改用真实入口，同时修复 Next 的中文边界校验。补充约束又发现 Uri.parse 会先规范化 `..`；最终在原始片段上完成校验，越界不会发出请求。
- WebDAV fixture 首稿没有 PROPFIND 响应中的目录自身记录，被现有客户端拒绝为 XML 405；补齐合法响应后通过，没有修改 Classic 的 XML 行为。
- 实验脚本最初从条件导出访问 dispose，静态分析选到不包含该方法的 stub；改用现有真实实验使用的 FFI import。最终脚本没有分析 error。
- 最重要的样本差异是原始两台媒体服务器根本没有提供非空 ProviderIds、年份和原名。保留这一观察，没有伪装成已经识别的平台身份。非空编号的覆盖来自明确标记的独立 fixture。

## 4. 需要主控决定的问题

没有。原始真实样本缺少非空平台编号属于实验覆盖限制；若后续提供服务器已匹配的样本，可直接用同一查询能力补验。此次没有改变 Classic 定位作用域或任何身份绑定契约。
