# DFM+ 停顿诊断

本工具记录实际帧编号和时序，用于定位“停住一次，随后跨过一段距离”。它不改变位置公式、提交节奏或 GPU 绘制行为，也不以日志采样代替显示器 Present 测量。

## 采集

1. 解压诊断 ZIP，关闭已经运行的 NipaPlay。
2. 双击与 `NipaPlay.exe` 同目录的 `Start-DfmTrace.cmd`。
3. 选择 DFM+，播放容易出现问题的片段 30–60 秒。保持窗口大小、显示器和超采样设置不变。
4. 记下停顿大约发生在开始播放后的第几秒，随后正常关闭播放器。
5. 返回 `dfm-traces/dfm-日期时间.jsonl` 文件，以及上述发生时间。无需先自行运行分析脚本。

正常双击 EXE 不开启日志。脚本只给新进程设置 `NIPAPLAY_DFM_TRACE`，退出后恢复脚本进程的原环境。日志不记录视频地址、文件名、弹幕文本或字体文件路径；采集少量进程内匿名对象 ID、坐标、播放时间、帧数和渲染参数。

日志自动限制为 10 分钟、128 MiB。Dart 保留最近 8192 个事件，每秒批量发送；Native 使用容量 16384 的非阻塞投递队列，由专用线程缓冲写盘，每秒 flush。两层溢出均计数。强制结束进程可能丢失最后约一秒；关闭窗口前可停留两秒，以便最后一批送达。

## 分析

```powershell
python tools/diagnostics/dfm_trace/analyze.py path/to/dfm-trace.jsonl
python -m unittest discover -s tools/diagnostics/dfm_trace -p test_analyze.py -v
```

在日志旁生成 `.summary.json`：每阶段 p50/p95/p99/max、各阶段帧间隔、最长等待对应的 engine/frame 编号、已处理但未观察到绘制的帧、重复的完成编号，以及坐标停住/反向移动样本。

判读必须结合播放阶段。启动、配置、seek、暂停、无弹幕时的间隔不等于故障；连续新帧合并成一次绘制也可能是正常追赶。分析器不把它们自动判成根因。`loss` 非零时先考虑采样不完整。

## 时序与边界

所有帧关联键都是 `(engine, frame)`；帧号由 Dart 全进程递增分配。`frame=0` 表示初始化/预取/非 DFM 来源，分析器不将它与位置快照配对。

| 域 | 事件 | 含义 |
| --- | --- | --- |
| Dart | tick | Ticker 到达；elapsed_us 是动画时间，t_us 是回调执行时刻，并附 in_flight/queued |
| Dart | snapshot | 已计算位置；记录播放时间、最多三个滚动条目的匿名 ID/x/y/speed、刷新率/DPR/超采样 |
| Dart | payload_begin / encode_begin | emoji/载荷准备开始，以及 JSON 编码开始 |
| Dart | send_begin / send_return | 编码完成后发送方法调用、收到返回；包括平台排队和原生同步等待 |
| Dart | flutter_frame | Flutter 原始 vsync/build/raster 时间戳；报告到达时间不能当成帧完成时间 |
| Native | ffi_enter / enqueue | 原生调用入口及入队之前 |
| Native | process_begin / process_end | 渲染线程处理帧数据；a 为处理成功标志 |
| Native | draw_begin / draw_submitted | CPU 构造绘制命令到提交返回，包含字形准备等成本 |
| Native | gpu_complete | wgpu 完成回调执行；a=完成序号，b=纹理代；包含回调派发延迟 |
| Native | notify_begin / notify_end | MarkTextureFrameAvailable 前后；frame=最新观察到的完成编号，a=最新提交编号 |
| Native | texture_sample | Flutter 请求共享纹理描述符；frame/a 同上 |

Native `t_us` 来自同一个 Rust Instant 原点。Dart `t_us` 来自 Timeline.now，Ticker elapsed 是另一条动画时间轴。跨域只通过帧号关联，不能直接相减；同域可以量化排队、阻塞和回调间隔。

**texture_sample 不是物理呈现证明。** 当前是一张可被覆盖的共享纹理；记录的完成编号是请求时观察到的状态，并不证明 ANGLE/DWM 读取了该编号对应的像素。如果 Ticker/坐标/提交/GPU 完成都连续而用户仍观察到重复画面，需用实际呈现跟踪继续排查。

目前单元测试验证日志/分析机制，并未在用户的 180 Hz 视频场景重现停顿；收到实机日志后再做根因判断。

## Workflow DLL 原生验证（2026-09-14）

使用成功构建 `34793771057` 的 DLL，运行 `native_probe.py`：180 次/秒目标节奏，900 次提交，60 条测试文字，1920×1080 纹理（对应 1280×720 的 1.5× 超采样）。该程序只运行原生管线，没有 Flutter 窗口、视频解码或实际 Present，不能作为完整播放器帧率基准。

```powershell
python tools/diagnostics/dfm_trace/native_probe.py path/to/rust_lib_nipaplay.dll build/native-probe.jsonl
python tools/diagnostics/dfm_trace/analyze.py build/native-probe.jsonl
```

900 帧均观察到处理、绘制提交及 GPU 完成，未报告日志丢失。首帧 `draw_begin → draw_submitted` 为 19.981 ms，第二帧 `enqueue → process_begin` 为 16.740 ms，时间线证明首帧占用渲染线程时，下一帧的同步调用确实在等待。此段发生在启动暖机，不能据此认定实际播放中的周期性停顿也来自同一原因。

本次原生处理耗时中位数 0.024 ms，绘制提交中位数 0.331 ms，GPU 完成回调延迟中位数 0.306 ms、最大 10.073 ms。后者包含 CPU 回调派发延迟，并非纯 GPU 执行时间。结果用于确认日志能区分阶段，后续仍需实际视频场景的数据。
