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
| Dart | position_save_begin / position_save_prepared / position_save_end | 播放进度保存开始、位置字典编码完成、偏好存储返回；只记录进度，不记录文件路径。异步存储的总耗时不等于 UI 阻塞时间 |
| Dart | position_save_error | 保存失败；记录对应进度，错误详情留在应用日志，不影响后续保存队列 |
| Dart | flutter_frame | Flutter 原始 vsync/build/raster 时间戳；报告到达时间不能当成帧完成时间 |
| Native | ffi_enter / enqueue | 原生调用入口及入队之前 |
| Native | process_begin / process_end | 渲染线程处理帧数据；a 为处理成功标志 |
| Native | draw_begin / draw_submitted | CPU 构造绘制命令到提交返回，包含字形准备等成本 |
| Native | gpu_complete | wgpu 完成回调执行；a=完成序号，b=纹理代；包含回调派发延迟 |
| Native | notify_begin / notify_end | MarkTextureFrameAvailable 前后；frame=最新观察到的完成编号，a=最新提交编号 |
| Native | texture_sample | Flutter 请求共享纹理描述符；frame/a 同上 |
| Native | pacing_wait_backend | 渲染线程启动时记录；a=1 表示高精度 waitable timer 和命令事件创建成功，否则退回普通通道等待 |
| Native | pacing_mmcss | 连续动画启动时的 MMCSS 注册结果；a=1 表示注册成功 |
| Native | vsync_pulse | 轻量 vsync 命令出队；a=Dart Ticker elapsed_us，b=原生入队至出队耗时（微秒） |
| Native | pacing_wait_begin / pacing_wait_end | a=计划等待/实际等待微秒；begin.b=高精度后端可用，end.b=是否收到命令（0 为超时或断开） |
| Native | pacing_draw | a=1 表示 vsync 驱动，a=0 表示原生截止时间兜底；与同 frame 的 draw_begin 关联 |

Native `t_us` 来自同一个 Rust Instant 原点。Dart `t_us` 来自 Timeline.now，Ticker elapsed 是另一条动画时间轴。跨域只通过帧号关联，不能直接相减；同域可以量化排队、阻塞和回调间隔。

**texture_sample 不是物理呈现证明。** 当前是一张可被覆盖的共享纹理；记录的完成编号是请求时观察到的状态，并不证明 ANGLE/DWM 读取了该编号对应的像素。如果 Ticker/坐标/提交/GPU 完成都连续而用户仍观察到重复画面，需用实际呈现跟踪继续排查。

连续运动模式以 `render_source` 关联原生绘制编号与低频 Dart 场景编号。场景约每 50ms 提交一次，不应再把 process 间隔当作动画帧间隔。先检查 draw_begin 间隔，再沿 pacing_wait_end、vsync_pulse、draw_submitted、gpu_complete 和 texture_sample 定位长间隔。等待超时事件应与同引擎前一个 wait_begin 配对，实际减计划才是等待迟到量；收到命令时提前返回属于正常唤醒。vsync 和超时兜底共用一个出帧状态，不是两条并行绘制流。高精度定时探针仅测独立线程唤醒，不能证明 Flutter/DWM 上屏稳定。

新版 `flutter_frame` 另有 `build_end_us`，用于区分 Dart 构建耗时与等待 raster 开始的时间；旧日志缺少该字段时不能把两段时间混为一谈。

## 实机样本：周期停顿（2026-09-14）

样本 `dfm-20260914-094404-465.jsonl` 未报告事件丢失。以下时间以第一条位置快照为零点，避开启动、暂停和纹理尺寸变化：

| 下一快照时间（秒） | 帧号 | 快照间隔（ms） | 前一帧 Dart 方法调用往返（ms） |
| --- | --- | --- | --- |
| 4.060 | 619 | 29.14 | 25.21 |
| 6.065 | 1000 | 31.82 | 25.84 |
| 8.066 | 1371 | 29.02 | 24.72 |
| 10.066 | 1740 | 31.56 | 25.30 |
| 12.066 | 2106 | 29.39 | 26.41 |

相同模式延续到约 22 秒。以帧 618 为例，原生 FFI 只耗时 0.111 ms，绘制提交 0.345 ms，GPU 完成回调延迟 1.597 ms；完成到纹理采样又隔了 23.254 ms。Dart 的 send_begin 后约 25 ms 没有事件，下一次 tick 的动画时间跨过 33.333 ms，位置相应推进。抽样条目没有在媒体时间推进时保持原坐标的异常。证据指向 Flutter 更新/采样侧停顿，而非这一周期内 Rust 布局或 GPU 工作量耗尽预算；尚不能证明实际显示器 Present 的内容。

代码中每前进 2000 ms 保存位置一次（时间阈值 3000 ms 与位移阈值使用 OR），调用 SharedPreferencesWindows 2.4.1；该依赖最终同步执行整个偏好文件的 `writeAsStringSync`。修复将此读写路径改成异步并串行写入，保留文件格式，并缓存首次成功取得的存储目录，避免重复执行 path_provider_windows 内的同步 Win32 目录和 EXE 元数据查询。原日志没有存储阶段标记，因此“每个尖峰均由该同步写入引起”还需修复版实机对照；新增存储标记用于核实关联，不以方法返回 Future 作为非阻塞证明。

## Workflow DLL 原生验证（2026-09-14）

使用成功构建 `34793771057` 的 DLL，运行 `native_probe.py`：180 次/秒目标节奏，900 次提交，60 条测试文字，1920×1080 纹理（对应 1280×720 的 1.5× 超采样）。该程序只运行原生管线，没有 Flutter 窗口、视频解码或实际 Present，不能作为完整播放器帧率基准。

```powershell
python tools/diagnostics/dfm_trace/native_probe.py path/to/rust_lib_nipaplay.dll build/native-probe.jsonl
python tools/diagnostics/dfm_trace/analyze.py build/native-probe.jsonl
```

900 帧均观察到处理、绘制提交及 GPU 完成，未报告日志丢失。首帧 `draw_begin → draw_submitted` 为 19.981 ms，第二帧 `enqueue → process_begin` 为 16.740 ms，时间线证明首帧占用渲染线程时，下一帧的同步调用确实在等待。此段发生在启动暖机，不能据此认定实际播放中的周期性停顿也来自同一原因。

本次原生处理耗时中位数 0.024 ms，绘制提交中位数 0.331 ms，GPU 完成回调延迟中位数 0.306 ms、最大 10.073 ms。后者包含 CPU 回调派发延迟，并非纯 GPU 执行时间。结果用于确认日志能区分阶段，后续仍需实际视频场景的数据。

## 第二次实机样本与编码隔离（2026-09-14）

`dfm-20260914-160145-315.jsonl` 证明仅异步落盘仍不足够：3.946、5.946、7.952、9.953、11.952、13.957、15.956、17.957 秒开始的八次进度保存，都与 24–28 ms 的快照间隔尖峰重合。位置字典准备约 3.8–4.1 ms；之后整份偏好文件的 JSON 编码和 UTF-8 转换仍在 UI isolate 执行。未观察到抽样条目位置算法本身停住或反向的异常。

这次修复把位置字典的读取后解析/修改/编码交给 `compute`，整个 read/modify/write 按请求顺序完成；Windows 偏好插件另将完整文件 JSON/UTF-8 编码放入 `Isolate.run`，主线程只接收最终字节并异步写入。正常退出先停止播放更新 Ticker，再等待最后位置和保存队列完成。原有文件格式、保存触发频率及弹幕时间推进逻辑不变。

只读编码对照（可传入已有偏好 JSON 路径，不输出配置值；不传则使用合成数据）：

```powershell
dart run tools/diagnostics/dfm_trace/preferences_probe.dart path/to/shared_preferences.json
```

在同一份 2,451,782 字节数据上，预热后分别运行 20 次编码。Windows 基准程序临时请求 1 ms 定时器精度，退出时配对释放；用 5 ms 定时器观察事件循环能否运行。主线程编码：操作耗时中位数 23.803 ms，定时器最大间隔 31.411 ms，超过 11 ms 共 20 次；后台编码：操作耗时中位数 23.802 ms，定时器最大间隔 7.256 ms，超过 11 ms 为 0 次。这是独立 Dart 基准，不是 Flutter/视频/DWM 的帧率测量，不能替代修复版实机回归。

实机验收要点：保存总耗时可能仍有二三十毫秒，但保存期间 tick、snapshot 和 raster 应持续推进；判断依据是原先与保存对应的帧间隔尖峰是否消失，而不是保存方法是否更快返回。
