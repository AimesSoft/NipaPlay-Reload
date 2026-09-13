# DFM+ 帧时序修复方案

日期：2026-09-13。依据：`docs/dfm_plus_frame_pacing_findings.md` 及本机 DX12 隔离复现。

## 目标与实施决定

采用三个可独立验证的改动阶段：修复 GPU 完成通知协议；把 Windows 纹理通知改为完成事件驱动；让 DFM+ 以 Flutter vsync 为唯一位置推进来源。前两阶段对应已复现的缺陷，第三阶段解决确定存在的高刷节流，并消除 DFM+ 二次插值的时间基准缺口。

本文件是实施方案，本次不修改生产代码。当前用户的实际复现平台与刷新率尚未确认，Windows 为首个验证平台；共享 Rust 代码与 DFM+ Dart 代码的改动必须进行跨平台回归。

目标链路：

```text
Flutter vsync 时间 → DFM+ 当帧绝对坐标 → 原生绘制并提交 GPU
                                            ↓
                                  专用完成线程驱动 device.poll
                                            ↓
                              记录完成序号，唤醒 Windows 事件
                                            ↓
                              通知线程通知 Flutter 有新纹理
                                            ↓
                                    Flutter 自行安排合成
```

GPU 完成事件负责通知，不充当动画时钟；高刷新率下的 CPU/GPU 工作量会相应增加，实际能否达到屏幕刷新率以呈现测量为准。

## 阶段一：可靠、可结束的 GPU 完成通知

### 1. 完成状态由消费者确认

在 Rust 增加由 `Arc` 管理的完成状态，建议独立文件 `engine/frame_completion.rs`，保存：

- 当前呈现目标的 `generation`。
- 当前代内的 `completed_sequence` 与 `consumed_sequence`。
- `closed` 状态。
- Windows 可选的事件句柄所有权对象。

这些字段由一把短临界区的 mutex 保护；每帧仅在完成和消费时进入，不在锁内执行 GPU 等待、Flutter 调用或线程 join。

绘制提交时分配递增序号，完成回调只推进 `completed_sequence`；新提交不清除已完成状态。`next2_engine_poll_frame_ready()` 保留现有 bool ABI，内部改成：当前代中 completed > consumed 时更新 consumed 并返回 true。多个完成事件可以合并成一次最新帧通知，不能要求通知次数与提交次数一一对应。

创建或更换呈现目标时增加 generation，并重置该代的消费基准。完成回调捕获提交时的 generation，旧代回调不得更新新纹理的完成状态。引擎移出 registry 时立即关闭完成状态，再发送 Stop；不等异步渲染线程退出才标记失效。

### 2. GPU 回调必须独立得到驱动

`EngineDeviceContext` 当前为共享 device/queue。为该 context 建立一个完成处理线程，不为每个弹幕实例创建忙轮询线程。

- 绘制实际提交后注册 `on_submitted_work_done`，注册完毕再唤醒完成线程。
- 使用条件变量和待处理代数合并唤醒。无待完成工作时休眠。
- 工作线程调用 `device.poll(PollType::Wait { submission_index: None, timeout: Some(50ms) })`，驱动已注册回调。这里等待的是调用时最新提交的快照，不是等待持续提交的整个队列永远变空。
- 在等待期间新注册的工作保留新的待处理代数，不能在等待返回时无条件清掉；超时也不丢弃待处理工作。超时后检查关闭/设备错误再继续。
- device lost 或不可恢复错误转入失败状态并唤醒必要的退出路径，避免反复重试形成高 CPU 循环。
- GPU 等待不能发生在 Flutter 平台线程，也不能阻塞弹幕 render/command 线程。

不再通过多做一次空 `queue.submit()` 来尝试驱动完成回调。整理绘制接口，使实际有提交的分支，包括空场景清屏，都能登记完成工作；没有目标或绘制失败不能伪造完成事件。

完成回调可能在 render 线程的 `queue.submit()` 内同步执行，也可能在完成线程内执行。因此回调只更新完成状态和发出唤醒，不调用 Flutter，不获取 engine registry 或插件纹理锁，不操作裸平台对象。

### 3. 阶段验收

把隔离 probe 的协议实验接到生产完成状态实现，减少复制代码造成的偏差，并补充独立状态机测试：

1. 完成 A、提交 B、消费：A 的通知仍然可见。
2. 连续完成多帧：允许合并，最后完成序号最终必须被消费。
3. 仅提交一帧后完全停止提交：有界时间内仍收到完成通知，不能靠下一帧驱动。
4. 切换 generation 后旧回调返回：不得产生新目标的完成通知。
5. dispose 与回调并发：不访问释放对象，不出现永久等待。

GPU 测试以 1 秒为宽松完成超时，而不是拿 16ms 当正确性断言；生产性能指标另行测量。

## 阶段二：Windows 用完成事件唤醒通知线程

### 1. 用 Win32 Event 替换 Sleep(16)

插件创建两个事件：自动复位的 frame-ready event，以及退出用的 stop event。通知线程等待 `WaitForMultipleObjects`，收到 frame-ready 后扫描当前仍注册的 surfaces，消费完成状态并调用 `MarkTextureFrameAvailable`；收到 stop 直接退出。

使用自动复位事件合并连续唤醒；完成状态序号才是真实数据，事件仅用于叫醒消费者，不表示有多少帧。扫描期间新来的完成会保留状态，并留下后续唤醒，不手动 ResetEvent 擦除并发通知。

增加仅 Windows 使用的 FFI，例如 `next2_engine_set_frame_ready_event(handle, event_handle)`：

- C++ 把插件事件提供给当前 engine。
- Rust 用 `DuplicateHandle` 获得自己的句柄副本，并以 RAII / Arc 管理。
- 完成回调只对拥有有效生命周期的副本调用 `SetEvent`。
- 解除绑定时清除 engine 持有的副本；正在执行的回调仍可安全持有其副本。
- 不向 Rust 传递 `SurfaceState*` 或插件 `this` 指针。
- 绑定完成事件后，如果已有未消费的完成状态，立即唤醒，覆盖“先完成、后绑定”的首帧窗口。

FFI 注册失败必须显式返回并走初始化失败/清理路径，不能悄悄保留一个永远不会唤醒的纹理。

### 2. 明确锁和销毁顺序

现有 `DisposeSurface()` 持有 `mutex_` 时调用 `StopTickThread()`，而 Tick 也需要该锁，存在 join 等待锁的死锁路径，随本阶段修复。

删除一个 surface：在短锁内从集合移除并确定是否为最后一个；释放锁后解除完成事件绑定。若需停线程，在锁外置 stop event 并 join，之后注销纹理和发送 engine dispose。当前 `UnregisterTexture` completion 持有 retired texture/binding 的方式继续承担平台纹理资源的延迟释放。

关闭整个插件：先阻止新注册并请求通知线程退出，在锁外 join，再解除所有事件绑定、注销纹理、关闭各 engine，最后释放插件事件原始句柄。Rust 回调持有的副本保证迟到唤醒不会访问无效 HANDLE，closed/generation 检查保证不会重新激活已移除目标。

通知线程扫描和调用 Mark 时持有插件状态锁，禁止 surface 同时被移除；该调用本身不能等待 GPU。不得形成 Rust 完成锁 → 插件锁的反向调用链。

这里不尝试更改 shared texture 的读写同步协议。完成通知可靠不等于消费者与下一帧 GPU 写入已建立完整栅栏同步；若呈现采样证实仍有同时读写问题，再单独设计纹理轮换/消费栅栏，不能声称事件通知解决了这类问题。

### 3. 阶段验收

- 最后一帧、暂停画面和空场景清屏都能独立触发通知。
- 通知不再被固定 16ms 周期限制。
- 随机时序模拟连续完成/消费，允许合并，但不存在永久漏唤醒。
- 反复打开/关闭、拖动窗口大小、全屏切换和多个 surface 共存，无死锁、无失效 texture 通知；至少执行 100 轮生命周期压力验证。
- 暂停且 GPU 工作完成后，完成线程与通知线程均阻塞休眠。

## 阶段三：DFM+ 统一到 vsync 坐标快照

### 1. 删除高刷提交门限

在 `dfm_plus_overlay.dart` 移除 `_minSubmitIntervalUs`、`_lastSubmitWallUs`、`_cachedRefreshRate`、`_maybeUpdateSubmitInterval()` 及对应门限判断。120/144/165/240Hz 都由实际 Flutter vsync 驱动，不再按照显示器标称刷新率决定固定 16ms 门限。

### 2. 位置使用 vsync 时间戳，不使用回调实际执行时刻

将 AnimationController 的间接回调换为直接 Ticker，使用其 elapsed 时间形成明确的动画时间轴。Stopwatch 保留用于测量耗时，不再参与每帧坐标推进。

一次播放周期内，记录一对锚点 `(mediaTimeAtAnchor, tickerElapsedAtAnchor)`，按 `mediaTimeAtAnchor + (elapsed - tickerElapsedAtAnchor) * playbackRate` 求位置时间。倍速修改时先以旧速率结算到切换时刻，再建立新锚点；暂停恢复、真实 seek/loop 和时间源更换时使用明确的重同步路径。保留现有 seek 判定策略，避免此次混入媒体同步策略重写。

分离监听器：

- Ticker 是播放时唯一的连续提交来源。
- playbackTimeMs 更新用于记录权威时间和 seek 判定，播放中不额外发起第二轮位置提交。
- 暂停、配置变化、窗口尺寸变化可申请一次刷新，使用冻结/重同步后的媒体时间。

### 3. 异步任务不得把旧坐标补交为新帧

保留一项 in-flight 工作和一项“待刷新”状态，不建立无限帧队列。异步操作结束后如跨过新的 vsync，下一次使用最新时间构建位置；播放时不在 while 循环中连续补交多个过期位置帧。

将 configure、texture ensure、首屏预热等准备步骤与最终位置快照分开。尤其修复当前 configure 重置显示时间后继续使用 await 前 `interpolatedTime` 的情况。首屏 200ms 预热结束后也应重新获取下一帧时间，不能提交预热前坐标。

Emoji 栅格和 prefetch 增量具有副作用，丢弃旧位置帧时必须保留未确认上传的字形数据，不可把含新字形的整份 payload 直接丢弃后又标记 atlas synced。缓存上传确认只跟随真正成功提交的 payload。

### 4. 显式关闭 DFM+ 的原生二次推进

为帧协议增加 `motion_mode`，DFM+ 使用 `vsync_snapshot`，旧 payload 缺省使用 `legacy_interpolation`。由 `Next2TextureBridge.setFrame()` 的显式参数统一写入根 payload，覆盖普通帧、emoji 帧、预热帧和清屏帧，避免只改某个旁路。

Rust `FramePayload` 解析该字段并保存在 renderer：

- `vsync_snapshot`：直接绘制提交的 x/y，`interp_dt=0`，`needs_interpolation_render()` 返回 false。
- `legacy_interpolation`：维持原有行为，兼容其他引擎与旧调用者。

DFM+ 坐标始终保留浮点值。该选择消除了“Dart 算一次位移，Rust 以接收时刻再补一次”的多时间源行为，也让暂停不再依赖 50ms 超时去猜测。

取舍：如果 Dart 本身只能生成 30fps，快照模式将如实呈现约 30fps，不再依赖未同步的原生 idle 插帧。此次目标是恢复健康流水线的高刷节拍；若弱设备仍明显受 Dart 计算限制，应另立统一原生时钟/运动模型任务，而不是恢复两个自由运行时钟混合推进。

### 5. 阶段验收

- Flutter 可控时间测试：60/120/144/165/240Hz 下，在无阻塞情况下每个 vsync 恰有一次提交机会；144Hz 不再出现固定每三帧一次。
- 同一个 vsync 内 playbackTimeMs 和配置通知并发，不产生两次动画位置推进。
- 模拟 setFrame/emoji/configure 延迟，队列有界；恢复后跳到最新进度，没有补交历史帧导致的回摆。
- 在连续、无 seek 的 RL/LR 弹幕中，坐标分别单调递减/递增；固定弹幕位置不变。测量 x 时允许浮点误差，不通过整数取整伪造稳定性。
- 暂停 1 秒、恢复、0.5×/1×/2× 切换、前后跳转和后台恢复均无额外时间累计。
- 已预热字形的轻负载场景必须覆盖健康高刷；密集弹幕、首次 emoji 和超采样单独测量资源压力，不混为时钟正确性问题。

## 文件范围

| 文件/模块 | 改动 |
| --- | --- |
| `rust/src/next2_engine/engine/frame_completion.rs`（新增） | 完成状态、代际隔离、device 完成线程、状态机测试 |
| `rust/src/next2_engine/present.rs` | 删除生产者清除、删除多余空提交、登记真实绘制完成 |
| `rust/src/next2_engine/engine/runtime.rs` | device 完成线程、engine 状态注册/关闭、目标 generation |
| `rust/src/next2_engine/ffi.rs` | Windows 事件绑定接口、dispose 失效时序，保留 poll ABI |
| `rust_builder/windows/rust_lib_nipaplay_plugin.{h,cpp}` | 事件通知线程、事件所有权、锁外 join |
| `rust/Cargo.toml` | 仅补充实际需要的 Windows API feature |
| `lib/danmaku_dfm/dfm_plus_overlay.dart` | 去节流、Ticker 时间、监听分离、异步后重取位置 |
| `lib/danmaku_next/next2_texture_bridge.dart` | 根 payload 的显式 motion_mode |
| `rust/src/next2_engine/engine/{frame,rendering,renderer_core,renderer_draw}.rs` | 帧模式解析与快照绘制 |
| `tools/diagnostics/next2_frame_pacing/`、相关 Rust/Dart 测试 | 回归复现与时序验收 |

## 跨平台与实际呈现验收

Windows 首先验证以上三阶段。macOS/iOS 保留现有 display-link 通知方式，通过兼容的 poll ABI 消费完成状态；共享完成线程确保末帧得到通知。Android 保留 Surface 呈现链路，不接入 Win32 Event。Linux 为独立 GL 渲染路径，不套用 DX12 完成线程/句柄逻辑，但需要验证新的帧模式与 DFM+ 提交行为。

增加默认关闭的诊断开关，采样 frame ID、采样媒体时间、提交/完成/通知序号、各阶段耗时。采用环形缓冲或每秒汇总，禁止逐帧同步日志引入新的卡顿。不同语言时钟未校准前只比较各自内部耗时，不直接相减得到“跨层延迟”。

最终以实际显示内容验收：用固定文本、固定速度、预热字形的场景连续观察至少 60 秒；关闭其他界面动画并补做暂停视频而弹幕诊断动画运行的测试，避免依靠视频重绘掩盖漏通知。对高刷使用匹配刷新率的捕获方式/外部高速录像；普通 60fps 录屏不足以验证 120/144Hz。

分别统计提交、GPU 完成、Flutter 通知和实际呈现。跳过的序号可能是合法合并；连续无新呈现、周期性重复帧和异常位移才是检查对象。轻负载下，以实际刷新周期 T 为基准，检查是否存在稳定的 2T/3T 台阶，并核对连续滚动是否出现无 seek 的方向反转。不能只用 GPU probe 的通知数宣称用户看到的模糊/抖动已修复。

按阶段一、二、三各保留一次结果，确保可以判断通知协议、Windows 调度和 DFM+ 位置时钟分别改善了什么。若完成后仍有周期性抖动，以呈现轨迹与时间记录继续定位，避免再次引入缺少时间依据的平滑补丁。
