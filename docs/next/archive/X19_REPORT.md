# X19：下载完整流程向 Agent 开放

2026-10-11，worktree `~/Desktop/nipaplay-next-wt/downloads-flow`，分支 `next/downloads-flow`。

## 1. 完成了什么

下载器设置、任务目录、实时文件详情、磁力预览、最近目录管理、完成扫描和文件播放均已接入 Agent。复用 Classic 的 `DownloaderSettingsProvider`、`TorrentDownloadService`、原生 rqbit 会话、设置、扫描记录和观看历史；没有新增下载后端或改动 Classic GUI / Rust 服务实现。

| 入口 | 行为 |
|---|---|
| `settings` 的 `download.enabled` | 调用 Classic Provider 启用 / 停用，GUI Provider 与持久设置一致。停用保留已有任务。 |
| `download.directory` | 设置默认绝对目录；空字符串恢复应用默认目录。使用 Classic setter 和最近目录持久化。 |
| `download.createFolderForTask` / `download.autoScanCompletedTasks` | 开放 Classic 的同名文件夹和完成自动扫描开关。 |
| `download.add` | 新增 `downloadDirectory`、`createFolderForTask`，只覆盖本次新任务。保留 magnet、HTTP(S) 种子 URL、本地种子和 `sources` 批量输入。 |
| `download.preview` | 用 Classic 解析磁力元数据，返回文件、大小、名称及目录建议；释放预览句柄，不添加任务。 |
| `download.directories` / `download.forget_directories` | 查看默认 / 最近目录；批量移除最近选择记录，不删除文件、不改变默认目录。 |
| `task.list` + `download.read` | 列出持久任务，再按 `jobId` / `jobIds` 批量取原生实时状态、速度、输出目录、文件索引、大小、included 和视频标记。已移除会话返回 `task: null`，原回执保留。 |
| 原有 `download.set_paused / pause / resume / remove / delete` | 继续复用既有批量控制、取消、保留文件移除和破坏性删除审计。 |
| `download.import` | 校验已完成本地视频的路径边界与真实大小，调用 Classic 完成文件扫描，读取实际识别结果，保存原扫描记录。不修改历史下载回执。 |
| `download.play` | 按 `jobId`、`fileIndex` 选视频，复用 Classic 磁盘 / 历史解析和串流播放。未入库的完整文件也能播放；未完成且暂停的任务沿用 Classic 播放按钮的恢复下载语义。 |
| 原有 `playback.open` | 移除任务后，仍可直接播放保留下来的本地文件。目录授权继续使用 `playback.authorize_directory`。 |

已检查 Classic 下载页、文件模型、Dart 服务和 Rust 导出：当前的文件选择是**选择播放哪个视频**。没有下载 inclusion 编辑、优先级调整或限速 setter / GUI 操作，因此没有新增这些能力。`included` 是实际后端清单的只读状态。

未 commit、push、运行 pub get 或更改依赖。构建自动刷新了 `macos/Podfile.lock` 中的 Erika pod 版本 / checksum；构建完成后已恢复该文件，最终依赖文件无 diff。

## 2. 决策

1. **设置使用现有 registry，写入调用 Classic Provider。** 没有另一套下载偏好，设置修改有来源与 revision，界面开关获得原 Provider 通知。目录读取不通过会补写默认值的 Classic getter，避免设置串行写入期间由读取引起嵌套持久化；读取未设置的目录不会写偏好或增加 revision。
2. **停用沿用 Classic 语义。** 隐藏 Tab、拒绝 Agent 新增；不把它解释为暂停全部原生下载。已有下载和完成文件仍可查询、控制、播放。
3. **单任务覆盖不改默认值，不迁移旧任务。** 目录选项进入原有 `DownloadRequest` 和任务 JSON。重复同一 hash 返回原任务；新目录不能借重复添加移动旧数据。绝对路径在 Agent 输入边界校验，平台书签继续交给 Classic，实验写入仍由 Lab profile 限制。
4. **实时状态与回执各自保留含义。** 已成功的下载也可能继续做种或暂停做种，`download.read.task` 返回当前原生状态；旧回执是完成时的观察，不因控制、扫描或播放而改写。
5. **扫描完成不冒充识别成功。** `download.import` 的 Action 完成表示扫描已运行，`files[].imported` 才表示读到了 Classic 识别记录。无身份时保持 `identificationPending`，不生成作品或剧集 ID。未识别文件的 Next 登记可以组合已有 `media.library.scan`，没有在下载代码里增加身份推断或另一份索引。
6. **播放复用 Classic 完整路径。** 选择 included 视频后，调用 `getPlaybackSource` 和 `PlaybackService.play`，保留 Classic 对未入库完整文件创建 fallback history 的行为；随后走已有文件登记包装。没有直接拼接 torrent 串流 URL 或绕过播放器启动。
7. **预览是独立原语。** 原生句柄在 `finally` 中释放；Agent 要实际下载时调用 `download.add`。最近目录管理也只操作现有选择记录。

## 3. 实验与验证

### 隔离环境与可复现材料

使用 Blender Foundation 的 [Sintel 预告片](https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4)，Sintel 按 Creative Commons Attribution 3.0 发布。原始样本为 4,372,373 字节、52.208333 秒：

```text
sha256=b670602fa00934ca27c4351bb0efe7ea7a07fae57284e44226025eeed7c51254
torrent infoHash=98250328f103ddfd8380a6631758f2bf76241626
```

[roundtrip.py](evidence/x19/roundtrip.py) 将未修改的预告片封装为开放授权测试种子，用临时 HTTP tracker、支持 BEP 9 的 TCP peer 提供元数据和真实 BT 分块。应用仍通过 Classic 原生 rqbit 下载，没有替换下载接口、预填目标文件或用 HTTP 下载冒充 BT。每块由 rqbit 校验，脚本最后逐字节比较目标文件与源文件。peer 每块稍作延迟，允许真实暂停和重连。此实验验证原生协议往返，不代表公网 swarm / DHT 的可用性。

只从本 worktree 的构建直接启动可执行文件，使用 `NIPAPLAY_PROFILE`；没有启动 `/Applications/NipaPlay.app`、调用 open / osascript、访问登录钥匙串或真实 NipaPlay 数据目录。应用进程移除了继承的代理环境变量，所有 Python 回环请求使用 `ProxyHandler({})`。实验预置的媒体授权根也在 profile 内，没有真实账号或令牌。

```sh
mkdir -p /tmp/nipa-next/x19
curl -kL --fail https://download.blender.org/durian/trailer/sintel_trailer-480p.mp4 \
  -o /tmp/nipa-next/x19/Sintel-trailer.mp4

ERIKA_PREBUILT_CACHE_DIR=/tmp/nipa-next/x2-erika-cache \
~/development/flutter-3.44.6/bin/flutter build macos --debug --no-pub

python3 docs/next/evidence/x19/roundtrip.py /tmp/nipa-next/x19/Sintel-trailer.mp4
```

脚本内部直接启动：

```text
NIPAPLAY_PROFILE=x19-downloads-20180
~/Desktop/nipaplay-next-wt/downloads-flow/build/macos/Build/Products/Debug/NipaPlay.app/Contents/MacOS/NipaPlay
PID=20182; restart PID=20255
```

完整端点输出保存在 [roundtrip.json](evidence/x19/roundtrip.json)，完整终端日志为 `/tmp/nipa-next/x19-roundtrip-complete.log`；应用日志为 `/tmp/nipa-next/x19-app.log`。

### 最终真实往返

按顺序执行：禁用状态添加被拒绝 → 设置默认目录并启用 → 查看 / 移除最近目录 → 磁力预览 → 按单项目录添加种子 → 暂停 / 恢复 → 校验完成 → Classic 扫描 → Next 文件登记 → 内部播放 / 定位 / 截图 → 暂停做种 / 停用 → 重启读回。

真实输出中的关键记录：

```text
download.add {"status":"failed","error":{"code":"unavailable","message":"Downloader is disabled.","retryable":false}}
download.preview {"status":"completed","result":{"name":"Sintel-trailer.mp4","suggestedFolderName":"Sintel-trailer","totalSize":4372373,"files":[{"index":0,"path":"Sintel-trailer.mp4","length":4372373}]}}
preview-without-task {"jobs":[]}
native-transfer {"wire":{"connections":3,"requests":271,"servedBytes":4437909,"metadataRequests":1},"actualBytes":4372373,"sha256":"b670602fa00934ca27c4351bb0efe7ea7a07fae57284e44226025eeed7c51254","defaultDirectoryEmpty":true}
```

三次 TCP 连接分别包含磁力元数据获取及暂停 / 恢复产生的文件连接；服务字节数稍大于文件大小来自重连重请求。默认目录为空，实际文件落在 `data/task-directory`，证明单项覆盖没有写入默认目录。批量添加中的第二项是无效磁力，独立返回 `invalid_input`，第一项正常下载。

入库前的 `state.query(view=library.files)` 返回 `rows: []`。本 profile 未登录弹弹play，Classic 扫描没有识别成功，输出 `imported: false, identificationPending: true`；应用日志记录扫描处理成功 0、失败 1。这不证明影片未收录，也没有把失败写成已识别入库。之后组合已有 Next 原语，实际登记成功：

```json
{"verification":"verified","details":{"indexed":1,"fileIds":["file-5654b8c5-911d-400d-a7eb-44d131fec494"]}}
```

随后 `library.files` 返回一个记录，`historyStatus: "no_history"`；`media.identity.get` 返回同一 fileId、一个真实 local location，`bindings`、`episodes` 均为空。这证明文件已入 Next 文件库，而不是伪造 Classic 作品 / 剧集身份。

`download.play` 调用生产 `PlaybackService`，真实内部播放器观察到：

```json
{"player":"internal","status":"paused","hasVideo":true,"paused":true,"animeId":null,"episodeId":null,"positionMs":23715,"durationMs":52208,"rate":1.0}
```

`playback.capture` 生成 2,369,718 字节 PNG。[实际播放画面](evidence/x19/sintel.jpg) 已打开检查，可见 Sintel 人物与建筑；没有用独立解码器或测试帧桥替代播放器画面。

控制后、扫描后、播放后以及重启后，下载回执保持逐字段相等。重启时原生任务仍暂停、目录和默认设置未改变：

```text
restart {"pid":20255,"jobId":"job-d088d8a49c53b8f8acb64fc8a0727b4f","receiptPreserved":true,"nativePaused":true,"outputDirectory":"~/Library/Application Support/NipaPlay/LabProfiles/x19-downloads-20180/data/task-directory"}
cleanup {"pid":20255,"processStopped":true,"profileDeleted":true}
```

### 未入库文件的播放

另一次隔离往返在任何 `download.import` / `media.library.scan` 前先执行 `download.play`，观察到完整本地文件直接播放，身份仍为空。记录在 [unimported-and-restart.json](evidence/x19/unimported-and-restart.json)，profile `x19-downloads-15358`，PID 15361 / 重启 PID 15442。其首次真实状态为 `player: internal, status: playing, durationMs: 52208`。这是 Classic fallback history 路径；入库不是播放前提。

所有四个实验 profile（12989、15358、17647、20180）均已按各自 PID 停止并删除目录。实验前期和最终运行均没有操作用户实例。
临时取样 / 种子目录 `/tmp/nipa-next/x19` 也已删除，保留仓库内的 JSON 证据、实验脚本、截图和上述终端日志。

### 失败与限制

- 首次直连 `webtorrent.io` 下载遇到证书链错误，随后直连超时；代理请求返回 HTTP 成功但内容是 `Web URL Filtering Service` HTML。解析时发现它不是种子，未交给应用。GitHub fixtures 的另一个 Sintel 种子实际指向 5.49 GB MKV，也未用作下载任务。
- 最终改用官方预告片和临时 BT 种子。下载公开样本的独立 curl 使用了 `-k`，因本机该请求的证书链校验失败；这是实验取样命令，应用的 TLS 验证没有改变。样本摘要、BT hash 和目标文件比较均记录了真实值。
- Classic 识别没有成功，本轮完整入库验证的是 Next 现有文件登记；没有验证某个作品的海报墙识别结果或公网 DHT 磁力解析。磁力元数据预览在真实回环 BT peer 上成功。
- 尚未完成的文件串流使用现有 Classic 路径，本轮窗口实验播放的是已下载完整文件。
- 新增测试最初因局部 helper 声明顺序及复用已关闭 engine 失败，已修正测试组织；最终没有测试失败。

### 数据约束与 Classic 回归

```sh
~/development/flutter-3.44.6/bin/flutter test --no-pub \
  test/next/download_executor_test.dart test/next/download_runtime_test.dart \
  test/next/builtin_download_backend_test.dart test/next/download_settings_test.dart \
  test/torrent_download_service_test.dart test/torrent_completed_scan_test.dart \
  test/torrent_session_storage_test.dart test/torrent_download_widgets_test.dart \
  test/torrent_task_controller_test.dart --reporter expanded
```

最终输出 `/tmp/nipa-next/x19-tests-complete.log`：

```text
00:04 +69: All tests passed!
```

新增约束验证目录选项持久化、重复添加不改旧目录、无效目录不产生任务、Provider 与持久开关一致、不改无关设置 / 扫描记录、读取默认目录不写偏好，以及扫描失败 / 文件大小错误不伪造身份或改写历史回执。原有迁移、扫描、控制和下载 GUI 回归保留。

新增能力、下载模块、设置、core 和相关测试的 focused analyze，日志 `/tmp/nipa-next/x19-analyze-complete.log`：

```text
Analyzing 8 items...
No issues found! (ran in 4.4s)
```

最终 Debug 构建成功（`/tmp/nipa-next/x19-build-complete.log`），`git diff --check` 通过。运行和构建都在本 worktree；GUI / Classic 服务源码没有修改。

## 4. 需要主控决定的问题

没有。Classic 识别失败、Next 文件登记与作品身份的区别、以及公网 swarm 未验证的范围已如实记录；没有修改这些既有产品语义。
