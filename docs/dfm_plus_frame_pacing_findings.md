# DFM+ 滚动弹幕时序排查（2026-09-13）

结论：已经在本机 DX12 上复现了共享渲染路径的 **GPU 完成通知丢失**。同时，DFM+ 的高刷节流确实会在 144Hz 下把 Dart 提交频率降到 48Hz。这两项是代码与实验能够确认的问题。用户实际出现症状的平台、刷新率尚未确认；本次没有录制播放器逐帧输出，不能把独立实验的通知次数当成播放器实测 FPS，也不能据此声称所有视觉抖动已经解释完毕。

## 1. 已复现：生产者擦除了消费者尚未读取的完成通知

位置：

- `rust/src/next2_engine/present.rs`：`signal_frame_ready()`。
- `rust/src/next2_engine/engine/runtime.rs`：`run_engine_loop()`、`poll_frame_ready()`。
- `rust_builder/windows/rust_lib_nipaplay_plugin.cpp`：`Tick()`、`EnsureTickThreadRunning()`。

现有执行顺序：

1. `draw_to_present()` 内部 `queue.submit()` 提交绘制。wgpu 同时可能派发已经完成的上一帧回调，将 `frame_ready` 置为 `true`。
2. 紧接着 `signal_frame_ready()` 无条件执行 `frame_ready.store(false)`，抹掉这个尚未被消费的通知。
3. 它又执行一次空 `queue.submit()`，然后才注册本帧的 `on_submitted_work_done`。
4. 普通原生渲染循环没有 `device.poll()`。当前帧 GPU 工作即使已完成，回调也通常要等到后续 `queue.submit()` 才得到派发。
5. Windows 独立线程每次 `Tick()` 后 `Sleep(16)`，只有恰好在 `true` 尚未被清除的窗口内运行，才能通知 Flutter。

这不是内存屏障不足：即使使用正确的 Release/Acquire，生产者依然在逻辑上覆盖未消费事件。`poll_frame_ready()` 已经通过 `swap(false)` 消费通知，生产者没有必要在下一帧提交时再次清除它。

wgpu 行为已对照本机实际使用的 `wgpu-27.0.1/src/api/queue.rs` 和 `wgpu-core-27.0.3/src/device/queue.rs`：完成回调需要 `submit` / `poll` 驱动，`Queue::submit` 会执行 `callbacks.fire()`。不能把该回调当成 GPU 完成后自动在后台调用的回调。

### DX12 复现

程序：`tools/diagnostics/next2_frame_pacing/`。使用 wgpu 27.0.1，GPU 为 NVIDIA GeForce RTX 5070 Laptop GPU。通过空 GPU 提交隔离通知协议，不含视频解码、文本栅格化、DFM 排轨和 Flutter 合成。

单线程阶段，连续四帧重复出现：

```text
frame 0: after draw submit, ready=false
frame 0: after GPU idle 17ms, ready=false, callbacks=0
frame 1: after draw submit, ready=true
frame 1: after GPU idle 17ms, ready=false, callbacks=1
frame 2: after draw submit, ready=true
frame 2: after GPU idle 17ms, ready=false, callbacks=2
frame 3: after draw submit, ready=true
frame 3: after GPU idle 17ms, ready=false, callbacks=3
```

随后以 120 次/秒提交两秒，消费者独立轮询并睡眠 16ms：

| 提交时清除标志 | 消费者主动 device.poll | 240 次提交收到的通知 |
| --- | --- | --- |
| 是（现有逻辑） | 否（现有逻辑） | 0 |
| 是 | 是 | 123 |
| 否 | 否 | 122 |
| 否 | 是 | 122 |

数值受线程调度影响，不应作为性能基准。实验说明现有协议可丢失全部通知，取消错误清除后可以恢复通知；约 122 次则受 16ms 消费周期限制。即使取消清除，缺少主动 poll 仍会造成通知延后一帧，以及末帧可能没有通知，因此修复必须同时处理回调驱动。

## 2. 已确认：高刷节流把 144Hz 变成 48 次提交/秒

`lib/danmaku_dfm/dfm_plus_overlay.dart` 的 `_maybeUpdateSubmitInterval()` 在刷新率大于 121Hz 时设置 16000 微秒阈值，提交后重新记基准。它不是精确的 60Hz 定时器。

| 屏幕刷新率 | 达到 16ms 需要的 vsync 数 | 理想稳定状态下 Dart 提交频率 |
| --- | --- | --- |
| 120Hz | 不节流 | 120Hz |
| 144Hz | 3 | 48Hz |
| 165Hz | 3 | 55Hz |
| 240Hz | 4 | 60Hz |

Windows 的纹理通知还有独立的 `Sleep(16)` 周期，理论通知上限约 62.5 次/秒，实际还要扣除 Tick 和调度耗时。它也不与显示器 vsync 同步。原生插值产生了额外图像，并不代表这些图像会在正确的显示时刻被呈现。

这里要区分通知频率与最终可见帧率：Flutter 的共享纹理可能随视频或其他界面重绘被重新采样，所以不能简单把上述通知上限等同于整个播放器的最终 FPS。缺失通知仍然破坏了纹理自身驱动重绘的链路。

## 3. 小幅抖动：存在可定位的时间基准缺口，视觉归因仍需播放采样

Dart 的 `DfmPlusLayoutBridge.layout()` 根据绝对时间计算 `x = width - speed * elapsed`，没有整数像素取整。Rust 主要预计算布局，这条生产路径的逐帧 x 更新实际上在 Dart 中同步执行。

但是，原生 `renderer_core.rs::update_frame()` 在解析、字体处理等工作之后设置 `submit_instant = Instant::now()`；`renderer_draw.rs::build_vertices()` 用 `x + scroll_speed * submit_instant.elapsed()` 推进位置。JSON 里没有携带 x 所对应的采样时刻。

设 x 在时刻 t 采样、传输和处理延迟为 L、真正绘制时刻为 R，则当前绘制等价于：

```text
x(t) + v × (R - (t + L)) = x(R) - v × L
```

因此不同帧的延迟变化会直接变成位置变化；例如 150 px/s 的弹幕遇到 10ms 延迟变化，就会偏移 1.5px。这证明当前插值没有消除传输延迟变化，但 **本次没有测到播放器内 L 的实际分布，不能据此确认它就是用户每隔几秒抖动的唯一原因**。独立通知时钟也会产生不均匀的呈现间隔，需先修复已复现的通知缺陷再观察残余抖动。

DFM+ 的媒体时钟 snap 阈值为 150ms，若滚动速度为 150 px/s，一次 snap 对应约 22.5px，量级远大于所述 1–2px。因此它不是本次优先修复对象。

## 集中修复方向

第一步修复完成通知协议：完成事件保留到消费者读取；在无需后续提交的情况下也能派发 GPU 完成回调。Windows 通知应由完成事件唤醒，避免继续依赖独立的 16ms 轮询。回调/唤醒方案需要处理 texture 注销和引擎销毁的生命周期，不能直接从异步回调捕获裸 SurfaceState 指针。

第二步删除 DFM+ 的高刷 16ms 提交门限，以显示节拍提交；然后对实际呈现序列采样，观察是否仍有 1–2px 回摆。若仍有，统一位置采样与渲染时钟，避免每次收到消息时重新设置不包含传输延迟的插值基准。不要通过像素取整、增加模糊或调整字体采样来掩盖时序问题。

本次只增加诊断程序和报告，未修改生产渲染逻辑。复现命令：

```powershell
cargo run --offline --manifest-path tools/diagnostics/next2_frame_pacing/Cargo.toml --target-dir rust/target/frame-pacing-probe
```
