# X47c：一个跨设备媒体库与文件通道

2026-10-13；worktree `~/Desktop/nipaplay-next-wt/x47-mesh-library`，
分支 `next/x47-mesh-library`。中断恢复后按用户新规范撤销只读、仅库内文件和
shareLibrary；沿用已通过的视频实验，只补新增行为。没有 commit 或 push。

## 1. 完成了什么

- 实现 `NextUiData.library()`：本机与同账号各设备的全部作品合并一份，最近添加在前。
  已接受的外部作品身份、明确季/集号和重复文件观察连接分散的剧集；本机重复优先。
  `work/episodes`、首页、卡片、`media.metadata.ui_facts` 接入同一投影，保留既有界面
  契约和 `ui.open {entityId}`。没有分类、筛选或分区实现。
- 远端目录和元数据在本机可读，图片/小型附件缓存成本机路径。离线保留上次目录、
  图片和进度，设备 online=false，只有离线来源的剧集 playable=false。
  定时/显式刷新、来源文件变化、进度或连通状态变化触发本机 changes。
- 远端播放沿用 Classic HTTP 播放入口，回环转换口支持 GET/HEAD/Range、206/416。
  **HTTP 只监听播放/调用端 127.0.0.1，默认随机端口，不对外开放明文端口。** 视频通过
  原 Mesh TLS 1.3 双向认证直接读取，使用 LAN/overlay/用户 SSH 候选，不经协调服务。
  Next 打开转换地址时临时清除播放器代理，普通播放恢复原设置。
- 同名弹幕/字幕、导入弹幕、绑定开关/偏移/时间段通过源端播放 bundle 提供。
  小附件可缓存，整部视频不复制。远端播放观察进入合并进度；本机 Classic 历史仍
  作为本机观察，合并 ID 可用原 watched-history 入口更新。
- `media.library.readable/refresh/progress` 和 `state.query library.merged` 可供 Nipa 使用。
  `media.mesh_files.readable` 批量提供任意可读绝对路径的地址；begin/chunk/finish/cancel
  提供写入原语，delete 批量预览，confirm 是 destructive 决定选项。
  删除和覆盖返回 NeedsDecision，确认前不改变目标，确认时检查预览是否仍成立。
- 加入 Mesh 是宿主同意。源端文件权限就是进程实际权限，没有 shareLibrary 和路径
  白名单；原共享开关的三个 settings 拒绝项已撤回，审查补充仅拒绝宿主 fileProxyPort 配置键。
  文件工具和目录协议无需 Classic receiver 审批；tools/list 可在已认证连接读取，
  其他既有工具调用的 Classic 审批保留。
- 无界面宿主注册相同目录、状态、文件能力，已构建并运行独立本机 AOT 实验。
  种子事实、Mesh/ui_data README、HEADLESS 和 X45_RUNBOOK 已更新。X45 主控已记录的
  `/UserId` 与 Windows 监听 47832/候选 47822 修正写回 runbook，没有重跑三机实验。

没有修改 `lib/next/ui/` 或 core_connect 接线。已有调用契约足够。
X46 合并关注 `mesh/runtime.dart`：仅增加 libraryRequest hook、目录/文件/工具列表的
已认证分派与许可分支；放行其他 Action、远端程序仍交给 X46。settings/denylist 新增三个
fileProxyPort 精确拒绝项，主控与 X46 合并时保留，未恢复 shareLibrary。

## 2. 决策与理由

1. **交换目录投影，不复制数据库。** 每 5 秒刷新（设备名单最多每 30 秒），目录分页
   带版本；分页期间变化拒绝整批。使用现有 ui_cache 存来源目录、ID 别名、首见时间、
   进度；不用数据库迁移。离线保留最近事实，恢复后交换。图片和小附件在 mesh-artwork，
   源端弹幕导出在 mesh-assets。没有订阅开关或 Agent 编排同步步骤。
2. **身份是已接受的事实。** 弹弹play、TMDB、Bangumi 的 accepted exact/contains
   身份（包含 release 的作品身份）可以合并作品，候选或相似标题不合并。单集在作品内
   按身份、明确季/集号、或相同文件与时间段做传递合并。无集号不猜。历史合并 ID 以
   来源引用持久解析，接受身份改变或重启后旧引用继续可用。
3. **重复文件观察采用大小及首尾各 64 KiB SHA-256。** 按 size/mtime 缓存，避免为
   SMB 媒体重复读完整视频。它有同首尾不同中段误判的可能，不是完整内容证明；文件
   传输可用完整 SHA-256 验证。作品排序使用已有最早绑定时间，没有时间事实时用首次
   观察并保留；不能恢复从未记录的历史入库时间。
4. **进度是可回退的观察。** 最近 UTC 时间优先，同时间 writer 设备 ID 决胜，允许
   未看与进度回退，不取历史最大值。通过单集来源及文件+时间段传播到各自缓存。
   播放器每 3 秒观察，宿主关闭补最后一次；批量先完整验证再保存。没有改写对端的
   Classic 数据库。冲突顺序依赖节点时钟，不能替代精确时间同步。
5. **读写通道有界且可组合。** 读取在原 TLS 连接上用带高位标记的 JSON 头与原始
   二进制响应，每段最多 1 MiB；内部 adapter base64 不进入网络 JSON 帧。写入段为
   512 KiB 解码字节的 base64 JSON，约 699 KiB 加协议头，满足已有 1 MiB 限制。
   父目录必须已存在；暂存完整文件再发布，相同偏移重试必须相同。不用预制搬移流程：
   读、写、校验、删除可由调用者按用户意图组合。chunk 内容 schema 标 secret，不入 journal。
6. **决定保持显式。** 覆盖/删除票据绑定认证调用设备；确认先校验目标内容/mtime/
   路径，变化拒绝；票据单次使用。传输和决定目前是进程生命周期内的设施，正常停止
   删除未完成暂存，异常退出可能留 `.nipa-transfer-*`。目标不在 begin 时被截断。
   没有新增宿主共享开关、路径允许表或依赖。
7. **Classic 接线仅在 Next 生命周期生效。** 弹幕/字幕回调对普通播放返回原路径，
   代理调整只作用于 Mesh 回环播放。无界面字幕匹配复用 Classic 纯 Dart fallback
   算法的独立纯 IO 版本，没有修改 Classic 的匹配代码。

## 3. 实验与检查

证据在 [evidence/x47/](evidence/x47/)，全部使用独立临时目录和本 worktree 构建。

| 证据 | 真实观察 |
|---|---|
| [loopback-second.txt](evidence/x47/loopback-second.txt)，中断前已通过，未重跑 | 两真实 TLS 节点：Mac 1–3 集、来源 1 和 4–12 集合并成 1 部/12 集，重复优先本机；图片成本机缓存。自制 CC0 640×360/24fps/12 秒视频 2,808,032 字节；Range 1048576–1048703 与源相同，suffix/HEAD/416 通过；ffprobe 得 12.000000 秒；ffmpeg -ss 8 解码帧与本地 MD5 同为 49179ecc48be43f8a133e05c27f5e58f。进度 .75→.25 跨节点可见，错误批次不部分保存；同名 XML/SRT 提供；离线保留目录和图像 |
| [x47c-files.txt](evidence/x47/x47c-files.txt) | 真实 TLS 读取未入库文件；写入 1,048,655 字节、三段，重试相同内容可接受、不同内容拒绝；SHA256 错误不发布；覆盖及批量删除 NeedsDecision；预览后目标变化拒绝；别的 peer 和确认重放拒绝 |
| [x47c-catalogue-passed.txt](evidence/x47/x47c-catalogue-passed.txt) | 两部目录接受相同 TMDB 身份后成为一部/一集；旧 work/episode ID 在合并和缓存重启后继续解析；canonical metadataFacts 可读；NaN 进度不写缓存；源文件移除后不替代可播放本机来源 |
| [x47c-headless.txt](evidence/x47/x47c-headless.txt) | 独立 Dart AOT + Rust C ABI 进程，真实认证目录含一部/一集；合并 metadataFacts 可读；Range 4096–4223 与源字节相同，字幕写入源媒体测试目录并发布；按本实例 PID/stop.request 停止，临时目录清理 |
| [x47c-tools-passed.txt](evidence/x47/x47c-tools-passed.txt) | Classic receiver 明确拒绝时，文件工具仍能通过 Mesh catalog/call 使用；决定包装为本机 mesh.invoke_destructive；普通 download Action 仍拒绝 |
| [x47c-local-constraints.txt](evidence/x47/x47c-local-constraints.txt) | 尚未加入 Mesh 的本机文件原语可用；调用 journal 不包含上传原始字节 |
| [full-regression.txt](evidence/x47/full-regression.txt) | 一次完整 test/next，加 player_http_proxy、subtitle_manager/candidate、danmaku_auto_load_strategy/track_timing；513 通过、10 跳过、1 失败：新增视图后旧数量断言 22 应为 23 |
| [state-query-regression.txt](evidence/x47/state-query-regression.txt) | 修正数量断言并避免空目录创建无意义缓存后，相关文件 16 项全部通过；未重复全量 |
| [analyze-delivery.txt](evidence/x47/analyze-delivery.txt) | 0 error / 0 warning，80 条 info（含已有和新增花括号风格提示） |
| [macos-build-final.txt](evidence/x47/macos-build-final.txt)、[macos-sign-verify.txt](evidence/x47/macos-sign-verify.txt) | Flutter 3.44.6 --no-pub Debug 构建成功，ad-hoc runtime 签名、deep/strict 验证成功；没有启动 GUI |
| [headless-native-build.txt](evidence/x47/headless-native-build.txt)、[headless-aot-delivery.txt](evidence/x47/headless-aot-delivery.txt) | Rust headless 离线 locked 编译成功（既有 unused/dead-code warnings），最终纯 Dart AOT 重新编译成功 |

已有四项 X47 实验在全量用 `NIPAPLAY_X47_REUSE_EVIDENCE=1` 显式跳过，另六项是原有
skip；避免重复成功实验。独立 headless 实验需显式
`NIPAPLAY_X47_HEADLESS_BINARY=/tmp/nipa-next/x47c-headless`，其它定向命令用对应 test name。
所有 Flutter 测试经 lockf 排队、去代理，回环 HttpClient 设 DIRECT。

失败记录保留：最早缺 metadata_facts import；目录演进夹具集号用了错误整数类型；
发现字幕数组传给 ObjectSchema 脱敏接口变 null；源文件删除后的公开状态 locator=null
暴露了目录 sampler 的错误假设，改从本机原始 location 读取并实际检查文件；跨 Mesh
Outcome 的测试泛型断言也修正。对应后续定向检查均通过。旧视频证据中的
`shareLibrary=false denied` 是已撤销规范的旧断言，**不再作为有效行为**；当前代码、
测试和种子已删除该逻辑，未为它重跑视频。

构建引起的 Podfile.lock 变化已恢复；原先 GeneratedPluginRegistrant 的生成差异保留。
没有改依赖、pub get、用户钥匙串/真实 profile/~/.codex，未访问 /Volumes/Media，
未 SSH 工作站、启动节点或真实模型对话。隔离源进程、协调器与测试节点已结束；
没有碰 ui-demo、主控实例、安装版 NipaPlay 或工作站已有进程。

## 4. 还缺什么与主控事项

- 没有实际 GUI/MDK 拖动控件验收。字节 Range 与真实 ffmpeg 定位解码成立，Classic
  播放器接线已构建且相关回归通过；不能把这些证据称为 GUI 实际播放验收。
- 没有 Windows/WSL 本轮重编译和跨机运行；X45 留存二进制需要主控换成 X47 版本。
  LAN/overlay/SSH 真实候选、工作站库和真实对话验收仍由主控运行监督。
- 进程重启后的文件传输续传、异常暂存自动回收尚未实现。目录与进度离线缓存持久，
  与文件传输票据的生命周期不同。没有修改片库分类或分区。

**需要主控决定的问题：没有。** 合并时核对 X46 的 runtime 分派改动与此处 hook；
上述真实环境验收属于已约定的主控工作。

## 5. 主控审查补充：转换口授权与固定端口

已撤销 `_hash([peer,source,tag])` 生成访问令牌的做法。每次发放 URL 使用
`Random.secure()` 生成 32 字节（256 位）随机值，以无填充 base64url 放入路径。
同文件再次发放生成不同令牌；令牌只保存在当前 MeshLibrary 实例内存中，关闭实例/
进程退出清空，同端口重启也不能复用旧地址。不存在的令牌返回 404。源 tag 改变、
离线、过期或吊销仍由原文件标记与 Mesh 身份校验拒绝字节读取。证据不记录有效 URL。

宿主在调用/播放端 `mesh.json` 使用 `fileProxyPort` 指定 **1024–65535** 的固定端口，
0/省略为随机。配置在宿主启动时加载，第一次发放远端地址才绑定；修改后重启生效。
没有 Agent 设置/修改 Action，注册表拒绝原名及 mesh. / mesh/ 两种配置键。
固定端口占用会退回随机，始终只绑定 127.0.0.1。`state.query mesh.file_proxy` 报告
requestedPort、实际 port、state、fallback 和 reason，不暴露令牌。端口占用原因是
requested_port_in_use；无效类型/低位端口拒绝并显示 invalid_configuration。
并发发放共用一个监听器，防止同时创建多个端口。

新增证据 [review-proxy-passed.txt](evidence/x47/review-proxy-passed.txt)：两个真实 TLS
节点，用小文本文件仅检查本次改动。由原公式推算的地址与未发放地址都是 404，
有效地址 200；随机令牌解码为 32 字节且每次不同；默认随机、固定端口、并发共用
监听器、同端口重启后旧令牌 404；同一 Dart 进程与独立 Python 进程占用固定端口
时都退回随机，状态视图准确；端口 80 拒绝、注册表拒绝三个宿主配置键。
首次定向测试失败记录在 review-proxy.txt：Dart 同进程端口占用会在 OS 绑定前返回
shared-flag 错误，没有平台 EADDRINUSE 编号；已明确识别此占用分支，其它绑定错误
仍传播。后续同时验证真实 OS 端口占用分支并通过。

[review-state-query.txt](evidence/x47/review-state-query.txt) 验证新增状态视图后视图数
24、所有视图排除秘密、读取不写数据，定向测试通过。已有全量回归和视频/定位播放/
无界面源实验未重复。本次新增状态没有 UI 改动。

最终定向分析 [review-analyze-final.txt](evidence/x47/review-analyze-final.txt) 为
0 error / 0 warning、48 条 info（花括号风格提示）。本 worktree 最新代码的
[macOS Debug 构建](evidence/x47/review-macos-build.txt) 与
[纯 Dart headless AOT 编译](evidence/x47/review-headless-aot.txt) 均成功；重新执行
ad-hoc runtime 签名后，[deep/strict 验证](evidence/x47/review-macos-sign-verify.txt)
成功。本轮没有启动 GUI 或工作站节点；构建自动生成的 Podfile.lock 差异已恢复，
没有改依赖或提交。合并时请保留 denylist 中新增的三个 fileProxyPort 精确键，
与 X46 对同文件的改动一并核对。

### 每 5 秒刷新带来的协议成本

按可达设备、已缓存直连路由、一次刷新快于 5 秒的稳态计算：**本节点对每个其他设备
每轮 1 次 snapshot 请求、1 次响应、1 个新 TCP 连接和 1 次 TLS 握手**，约 12 次/分钟。
即使目录版本没变，也下载第一页；当前不是只传版本号的轻量探测。地址缓存复用的是
路由，Rust `Node.send` 每次仍新建 TCP/TLS；无 0-RTT。TLS 会话恢复是否减少握手的
内部开销没有单独测量，不改变每次请求新建连接和握手的事实。

每个节点都读其他节点，所以同一对设备双向合计约 24 次请求/握手每分钟；N 个全互见
节点合计每轮 N(N-1) 次，约 12N(N-1) 次/分钟。三节点稳态是全网 72 次/分钟，每台
发出 24 次、接收 24 次。目录变更且分页为 P 页时，该轮是 P 次 snapshot 请求/握手；
新图片/附件另增加每个文件 1 次 file 元数据调用，以及 ceil(size/1MiB) 次 read 调用/
握手。首次寻找地址和每 30 秒设备快照刷新另访问协调控制面，不是设备间 TLS 通道。
候选失败可增加连接尝试；刷新耗时超过周期时 `_sync` 合并重叠 tick，频率低于上述稳态。

**用 X45 的变化事件替换目录轮询可行，但不是原封不动接下载回传就足够。** 已有
持久批次、来源设备认证、ACK/去重与失败重送可以用于推送目录版本失效通知，接收端
合并通知后仅在新版本时拉目录。事件不需要唤醒 Nipa 或携带对话指令，属于数据同步。
当前下载回传绑定原会话/票据和 agentDeviceId，不是向所有组网读取者发布全库变更；
已有 library.file_added 也不覆盖身份、元数据、绑定、字幕选择、进度回退、外部文件
改写/删除及 Classic 历史。因此需补齐所有这些失效来源、读取者登记及重连补账。
首次连接/重连仍需版本核对或全量拉取，不能只靠在线时的事件。

离线节点无法发送事件，离线判定还要依靠低频可达性探测或长连接断开/心跳；现有
Mesh 一连接一请求不是持续订阅通道。可先用事件减少目录数据量与扫描，再降低兜底
版本/活性探测频率；若保留每 5 秒探测，握手数量本身不会消失。本次仅说明，没有
改变同步实现。需要主控决定的问题：没有。
