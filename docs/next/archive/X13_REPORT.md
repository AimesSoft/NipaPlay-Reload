# X13：播放能力开放

2026-10-11，worktree `playback-caps`，分支 `next/playback-caps`。

## 1. 完成了什么

缺口 3、4、5、9、10 的能力入口已实现并接入 `NextRuntime`。未 commit、push、改依赖或运行 pub get；未连接正在运行的 NipaPlay Agent 端点，未退出或重启用户实例。

| 能力 | 输入与结果 |
|---|---|
| `playback.open` | `path` 支持首次本地文件、file URL、串流 URL、`jellyfin://itemId`、`emby://itemId` 和 Classic 已支持的其他远程路径。观看记录可为空；原有按 anime/episode ID 选文件的决策流程保留。 |
| `playback.state / set_paused / seek` | 共用播放器端口；存在外部会话时控制该会话。`open.startPositionMs` 也可定位可控制的外部播放器。实际启动类型来自播放器状态，避免外部启动失败后内部回退却仍回报 external。 |
| `playback.authorize_directory` | 发起 Classic 文件夹选择器，复用平台授权/书签；返回选中路径，取消返回 null。 |
| `playback.tracks / select_track` | 列出内嵌、外挂和服务器轨道。按 `kind`、`origin`、`index` 选择；字幕索引 -1 关闭内嵌或服务器字幕选择。 |
| `playback.load_subtitle / remove_subtitle` | 挂载本地或 HTTP(S) 外挂字幕，返回实际本地路径和 active 状态；写入 Classic 字幕缓存列表。取消挂载保留字幕文件。 |
| `playback.stream_options / select_stream` | 读取版本、服务器音轨/字幕、8 个质量预设及当前转码选择；可批量设置 mediaSourceId、quality、transcode、audioIndex、subtitleIndex、burnIn，走 Classic 重载。 |
| `playback.external_state / external` | 读取实际遥测；pause、resume、seek、close。mpv/mpv.net 走 IPC，VLC 走现有 RC，PotPlayer 走现有 Windows 消息接口。generic 无遥测/控制时明确返回 unavailable 或 null。 |
| `playback.close` | 关闭当前外部会话，或调用内部播放器的正常 reset/save-progress 路径。 |
| `playback.capture` | `kind=screenshot` 实际生成 PNG/JPEG；`kind=gif` 实际调用 Classic GIF 导出。返回保存路径、字节数，GIF 还返回尺寸和帧数。已有输出文件返回 conflict。 |

生产代码使用 `PlaybackService.play`、`VideoPlayerState`、Classic 字幕/远程字幕服务、Jellyfin/Emby 服务、转码 Provider、现有外部会话和 Erika GIF 导出。NipaPlay/Cupertino 的内嵌轨道菜单改为调用同一组状态方法，方法执行原来的 setter；菜单的偏好保存和交互流程保留。

## 2. 决策

- **观看记录提供恢复信息，不作为播放许可。** 有记录照旧传入；新路径只构造 `PlayableItem`，不在能力层伪造观看记录、作品或剧集 ID。本地新路径验证绝对路径和文件可访问性；file URL 归一为同一个本地历史键，其他合法 URL 交给 Classic 处理，不另设协议白名单。
- **目录授权由已有系统选择器完成。** Agent 可以发起，不声称凭一个路径字符串就获得操作系统授权。macOS 书签和 Android SAF 仍由 Classic 处理。
- **轨道索引区分来源。** embedded 是播放器 `mediaInfo` 中的索引，server 是服务器流索引；不混用。外挂字幕通过返回的本地路径加载/取消挂载。
- **服务器选择沿用 Classic 语义。** 质量和转码开关保存到原 Provider 的默认设置。Emby 显式轨道选择传入恢复 bundle，并在成功后保存原有偏好 patch；换版本时复用其解析器。Jellyfin 重载和字幕下载增加可选 mediaSourceId，原 GUI 调用保持默认行为。Jellyfin 直播放时把服务器索引映射到内嵌轨，服务器外挂字幕走 Classic 下载与字幕堆栈，避免只更新选择记录却没切轨。
- **回执只返回允许观察的元数据。** 版本信息不包含认证串流 URL。外部会话不输出其可能带令牌的启动路径；`external_state` 返回 null 表达未知进度。保留原 snapshot 的整数字段兼容性，额外的 `external.positionMs/paused` 才是外部会话的可空读数。
- **命令后的状态来自会话。** mpv 定位原本会乐观更新位置，新遥测接口再查询实际 IPC；可控制会话启动时有界等待遥测，发命令后查询实际状态。VLC/PotPlayer 也暴露其已有查询路径。回执可能反映尚未完成的命令，调用方读取 observed state 判断。
- **媒体导出返回文件。** 截图复用 Classic 捕获/编码/默认保存目录，也允许指定 PNG/JPEG 输出路径；GIF 复用现有导出，范围在当前视频内、最长 30 秒。不新增编码依赖。
- **导出和字幕路径不进入视频索引。** 新控制能力直接注册，避开原 `FileIndexingCapability` 的“所有 path 都是媒体位置”包装，防止把截图、字幕、授权目录记成视频。

## 3. 实验与验证

### 隔离真实媒体实验

`test/next/playback_caps_experiment_test.dart` 是显式启用的实验，默认跳过。使用 SharedPreferences mock、内存凭据库和 `/tmp/nipa-next/x13` 存储；HTTP 客户端强制 DIRECT。临时账号登录信息只从给定 JSON 读取，不写入报告或日志。

实验从只读的 `~/Documents/nipaplay/downloads/Sintel/Sintel.mp4` 复制封装出 20 秒 MKV，包含两条音轨和一条字幕；原视频及“莉可丽丝”目录没有写入。空历史的 `playback.open` 真正启动独立 mpv，以 `--vo=null --ao=null --pause --no-config` 解码，不创建播放器窗口。Jellyfin 首次打开也用空历史，解析会话使用 Classic 服务，最后由独立 mpv 实际解码。

轨道选择通过播放器适配桥发送真实 mpv IPC。外挂字幕使用真正的 Classic SubtitleManager、解析器和缓存，远程字幕由本次实验的回环 HTTP 服务提供。截图将 mpv 在第 10 秒捕获的真实帧交给 `VideoPlayerState.captureScreenshot` 编码并保存；这是帧来源的测试适配桥，**没有验证 Flutter 纹理/窗口截图**。GIF 调用实际 Erika native headless 导出库。外部控制和共享 `VideoPlayerStatePort` 使用真实 `MpvSession`。

复现：

```sh
X13_EXPERIMENT=1 \
ERIKA_CAPI_DYLIB=/tmp/nipa-next/x2-erika-cache/v0.2.1/erika-capi-macos-universal/unpacked/erika-capi-macos-universal/lib/liberika_capi.dylib \
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/playback_caps_experiment_test.dart --reporter expanded
```

最终真实输出（完整日志 `/tmp/nipa-next/x13-experiment.log`）：

```text
X13 local: history=null path=/tmp/nipa-next/x13/first-open.mkv decodedDurationMs=20084
X13 actual mpv selection: aid=2 sid=1
X13 local subtitle: {"path":"/tmp/nipa-next/x13/external.srt","active":true} text=X13 external subtitle
X13 remote subtitle: {"path":"/tmp/nipa-next/x13/remote_subtitles/391349ee58fb15f7d636aa823d4ee1f10bba5aa5.srt","active":true}
X13 Classic PNG from actual mpv frame: {"path":"/tmp/nipa-next/x13/capture-1791693093302.png","bytes":516347,"kind":"screenshot"}
X13 actual Erika GIF: {"path":"/tmp/nipa-next/x13/capture-1791693093688.gif","kind":"gif","bytes":84999,"width":320,"height":180,"frames":6}
X13 external: resume=false pause=true seek={"active":true,"player":"mpv","processId":54756,"paused":true,"positionMs":5000,"telemetryAvailable":true,"durationMs":20084,"fraction":0.24895439155546703}
X13 shared playback port: player=external positionMs=7000
X13 external closed=true
X13 Jellyfin: history=null path=jellyfin://27ecb73cfb8fab575186e08e6fbdd58e decodedDurationMs=140032 versions=1
X13 Jellyfin options action: versions=1 qualities=8 source=27ecb73cfb8fab575186e08e6fbdd58e
X13 Jellyfin negotiation: selectedSourceMatches=true isTranscoding=true protocol=hls
X13 Emby negotiation: versions=1 selectedSourceMatches=true isTranscoding=true burnInRequested=true subtitleMethod=null
00:04 +1: All tests passed!
```

PNG 已打开检查，显示 Sintel 山景与片头文字。文件识别为有效 PNG（1024×436）和 GIF（320×180）。Jellyfin/Emby 的版本 ID 和转码协商在真实回环服务器上成立；此样本各只有一个版本，因此未证明多版本切换。Emby 请求了烧录，但返回 URL 没有 SubtitleMethod；不能据此宣称画面已经烧录。

### 自动化约束与回归

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/playback_controls_constraints_test.dart \
  test/next/playback_capability_test.dart \
  test/subtitle_manager_regression_test.dart test/remote_subtitle_cache_test.dart \
  test/jellyfin_authorization_test.dart test/emby_external_subtitle_selection_test.dart \
  test/media_capture_dialog_input_test.dart test/external_player_console_service_test.dart \
  --reporter expanded
```

最终输出：`00:03 +112: All tests passed!`，日志 `/tmp/nipa-next/x13-targeted.log`。新增约束覆盖首次路径不伪造历史/身份、不改输入文件、file URL 与本地路径复用同一身份、非 HTTP 协议转交 Classic、拒绝覆盖输出文件、拒绝无效轨道/GIF 区间、无外部会话不捏造进度。原有 Classic 字幕、GUI GIF 输入、认证和外部控制回归保留。

能力代码、runtime 和相关测试的 focused analyze 输出：

```text
Analyzing 5 items...
No issues found! (ran in 5.0s)
```

修改的 Classic 服务/外部会话代码分析无 error/warning；宽范围检查另有原本未使用的私有方法和既有 print 等 lint，没有做无关清理。`git diff --check` 通过。

额外跑了整个 `test/next` 加上述 Classic 回归：`+409 ~1 -1`，唯一失败为 `harness_hooks_test` 的并发 hooks 成功状态断言。单独复测该文件：`00:03 +3: All tests passed!`。未修改 hooks；不能把宽套件写成全绿。日志分别为 `/tmp/nipa-next/x13-regression.log`、`x13-hooks-recheck.log`。

实验中的意外：最初帧桥缺少 DecoderManager 所需的测试方法，出现 UnimplementedError，已补齐；初次回环发现请求用了 `X-Emby-Token` 而得到 401，换成服务器接受的 MediaBrowser 认证格式后成功，不能把这个 401 解释为账号或令牌失效。最初第 0 秒截图是视频本身的黑色片头，改到第 10 秒后得到可见山景。

### 留给主控的真机验证

这些是验证执行事项，当前没有操作用户真实实例：

1. 在主控的隔离实验配置里用新文件/URL 调 `playback.open`，确认 **生产 `PlaybackService` → 页面切换 → 真正的内部播放器窗口** 完整链路。无窗口实验替换了 start 边界，没有覆盖这部分。
2. 调 `playback.tracks`，分别用返回的 embedded/server 索引切音轨和字幕；加载本地、远程外挂，确认 Classic 菜单显示同一状态及字幕叠层；取消挂载后文件仍存在。GUI 自己再切一次，确认行为一致。
3. Jellyfin/Emby 用 `stream_options.versions[].id` 设置 `select_stream.mediaSourceId`，验证真正的多版本切换、位置/暂停恢复、Emby 偏好恢复。用 `{quality: "bandwidth1m", transcode: true, subtitleIndex: 实际索引, burnIn: true}` 检查烧录画面；再用 `{transcode: false}` 回原画。尤其核对 Emby 的烧录结果，回环协商不能代替画面证据。
4. 内部窗口调用 `playback.capture` 保存截图/GIF，确认纹理/平台画面、字幕和弹幕开关按现有 Classic 捕获行为呈现。无窗口 PNG 已证明真实帧编码/保存，但没有覆盖 Flutter RenderRepaintBoundary 或 Erika 窗口快照。
5. 发起 `playback.authorize_directory`，验证系统选择器及重启后的书签/SAF。mpv 已实测；VLC 和 Windows PotPlayer 的真实平台控制待对应环境验证。

## 4. 需要主控决定的问题

没有。上述真机验证及宽回归的 hooks 偶发失败需要主控在集成实验中复核，不涉及本批次新的产品或架构决策。
