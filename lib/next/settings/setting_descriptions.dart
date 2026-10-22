/// 每个设置的含义说明，供 `settings.describe` 返回。
///
/// 每条都来自读代码：写入它的 setter、读取它的渲染或播放代码、Classic 设置界面
/// 里对应的名字和档位。只写事实，不写判断或推荐。读不出来的写“未能从代码确定”。
/// 新增设置必须在这里补一条；`test/next/settings_descriptions_test.dart` 会检查。
library;

/// 把“什么时候生效”接在说明后面。`immediate` 不加字：即时生效是默认，
/// 运行中的值与保存的值是否一致由 effective 给出。
String describeWithApply(String description, String apply) =>
    switch (apply) {
      'reload_player' =>
        '$description 生效方式：保存后不打断正在看的媒体，下次打开媒体时重建播放器再生效。',
      'restart_app' => '$description 生效方式：只保存偏好，重启应用后生效。',
      _ => description,
    };

/// application_settings.dart 里注册的设置。
const applicationSettingDescriptions = <String, String>{
  // ---- 音量、亮度 ----
  'player.volume':
      '普通播放音量，0–1；桌面控制播放器并保存 Classic 音量，移动端控制系统音量。与音量增强（player.volumeBoost）独立。',
  'player.brightness':
      '移动端应用亮度，0–1；即时生效，不保存为长期偏好。',

  // ---- 播放器界面 ----
  'player.pauseOnBackground':
      '应用切到后台或锁屏时自动暂停播放。只在手机上提供；移动平台默认开启。',
  'player.desktopHoverSettingsMenuEnabled':
      '鼠标移到播放器最右侧时弹出设置菜单。只在桌面端提供，默认关闭；关闭时已弹出的菜单会收起。',
  'player.instantHidePlayerUiEnabled':
      '鼠标移开后立即隐藏播放器的控制界面，不等待延时。只在桌面端提供，默认关闭。',
  'player.showMenuQuickControls':
      '在播放器菜单顶部显示倍速和音量增强的快捷选项。Classic 设置页名称：播放器菜单快捷调节。默认关闭。',
  'player.topSendDanmakuButtonVisible':
      '在播放器左上角显示“发弹幕”按钮。默认开启。',
  'player.topSkipButtonVisible':
      '在播放器左上角显示“跳过”按钮；按下后向前跳过 seek.skipSeconds 秒。默认关闭。',
  'player.topResizeButtonVisible':
      '在播放器左上角显示“窗口适配视频”按钮，把窗口调整到视频的比例。默认关闭。',
  'player.topFrameStepButtonsVisible':
      '在播放器左上角显示逐帧后退和逐帧前进两个按钮。默认关闭。',
  'player.chapterMarkersEnabled':
      '在进度条上画出 MKV 自带的章节分割线，悬停高亮、点击跳到该章节。只在 Media Kit（libmpv）内核下提供，默认开启。',
  'player.minimalProgressBarEnabled':
      '播放时在播放器底部显示一条细进度条。Classic 设置页名称：底部进度条（外观页）。默认关闭。',
  'player.minimalProgressBarColor':
      '细进度条和弹幕密度曲线的颜色，ARGB 整数。只接受 Classic 的五个预设：0xFFFF7274 红（默认）、0xFF40C7FF 蓝、0xFF6DFF69 绿、0xFF4CFFB1 青、0xFFFFFFFF 白。',

  // ---- 解码与内核 ----
  'player.useHardwareDecoder':
      '是否使用硬件解码，只对 MDK 和 Media Kit（libmpv）内核生效；Classic 在其他内核下不显示。关闭时 libmpv 的 hwdec 固定为 no（软解），player.hwdecMode 此时不被使用。默认开启。',
  'player.hwdecMode':
      '硬件解码方式，取值是 mpv 的 hwdec 名：no 软解、auto 自动（任意可用解码器）、auto-safe 自动（最佳解码器）、auto-copy 自动（带拷贝），以及各平台的具体方式（d3d11va、d3d12va、dxva2、videotoolbox、vaapi、nvdec、mediacodec、vulkan、amf、qsv 等，带 -copy 后缀的是非直通版本）。Media Kit 内核直接设为 mpv 的 hwdec 属性；MDK 内核下 auto 系列沿用 useHardwareDecoder 的解码器偏好，具体方式会强制使用对应解码器。仅在 player.useHardwareDecoder 为 true 时使用；Classic 设置页没有对应控件。',
  'player.softDecodePixelFormat':
      '软解输出的像素格式名（FFmpeg 的 pixel_format，例如 yuv420p）；空字符串表示自动，使用内核默认。目前只对 MDK 内核的软解生效，硬解输出由硬件决定，不使用此值。Classic 设置页没有对应控件。',
  'player.kernel':
      '播放器内核：mdk（MDK）、videoPlayer（Video Player 官方播放器）、mediaKit（Libmpv，基于 mpv）、erika（Erika，Rust 编写的实验内核，在 Classic 里需先开启 labs.enableErikaPlayerKernel 才显示，电视和 HarmonyOS 默认显示）。可选值取决于平台。换内核会重建播放器。',
  'player.fastPlaybackStartup':
      '视频就绪后跳过“识别加载”界面，立即开始播放，再在后台识别番剧、加载弹幕。Classic 设置页名称：快速开始播放。默认关闭。',
  'player.customUserAgent':
      '播放器请求视频时使用的 User-Agent；空字符串使用内核默认值，下次打开视频生效。',
  'player.macosNativeVideoEnabled':
      '实验性 HDR 原生视频输出：开启后 macOS 使用原生视频层，关闭则回退到 Flutter 纹理路径。只在 macOS 提供（Classic 在 Media Kit 内核下的 macOS 与 Windows 显示），默认关闭。',
  'player.androidAudioOutput':
      'Android 的音频后端：opensles（OpenSL ES，默认，兼容性较好）或 audiotrack（AudioTrack，可支持部分机型的杜比全景声等系统音效，实验性）。只在 Android 提供，Classic 在 Media Kit 内核下显示。',
  'player.erikaAndroidOutputMode':
      'Erika 内核在 Android 上的视频输出：sdr 为 8-bit sRGB 输出，HDR 视频会映射到 SDR；extendedLinearHdr 为扩展线性 scRGB 的 HDR 输出（实验性），设备不支持时回退 SDR。只在 Android 提供。',
  'player.doubleResolutionPlaybackEnabled':
      '以 2 倍分辨率渲染画面，改善内嵌字幕清晰度。只对 Media Kit（libmpv）内核生效，不与 Anime4K 叠加。Classic 设置页名称：双倍分辨率播放视频。默认关闭。',
  'player.anime4kProfile':
      'Anime4K GLSL 着色器画质预设，用于提升二次元画面清晰度；只对 Media Kit（libmpv）内核生效。off 关闭；lite 轻量（x2 超分辨率加轻度降噪，开销较小）；standard 标准（恢复纹理加超分辨率）；high 高质量（高光抑制、恢复和超分辨率，画质最佳，对性能要求最高）。',
  'player.crtProfile':
      'CRT GLSL 着色器预设，模拟显示器质感，可与 Anime4K 叠加；只对 Media Kit（libmpv）内核生效。off 关闭；lite 轻量（扫描线加暗角）；standard 标准（再加曲面与栅格）；high 高质量（再加辉光与色散，开销最高）。',
  'player.erikaUpscalerMode':
      'Erika 内核的实时超分辨率（ART-CNN）：off 关闭；erikaArtCnnC4F16 半精度，速度优先；erikaArtCnnC4F32 单精度，画质优先，GPU 压力更高；erikaArtCnnC4F16Ds 半精度去噪锐化，适合压缩痕迹明显的动画。只在 Erika 内核下提供。',

  // ---- 播放行为 ----
  'player.introSkipEnabled':
      '总开关：开启时结合 AniSkip 社区标注和弹幕报点，在片头、片尾区间显示跳过按钮；AniSkip 有数据时以它为准，没有才用弹幕分析的结果。关闭时清除已有的跳过区间。默认开启。',
  'player.timelinePreviewEnabled':
      '启用 MDK 时间轴截图预览：进度条悬停时显示缩略图，仅对本地、WebDAV、SMB、共享媒体库的视频生效。会创建后台播放器并增加解码与缓存开销；应用内先显示 Classic 性能警告，由用户选择。只在 MDK 内核下提供，默认关闭。',
  'player.autoFullscreenEnabled':
      '加载视频后自动进入全屏。只在桌面端提供，默认关闭。',
  'player.autoNextCountdownSeconds':
      '播放结束后，等待多少秒再自动播放下一话，范围 0–15；0 表示不倒计时，直接播放下一话。仅当 player.playbackEndAction 为 autoNext 时使用。',
  'player.playbackEndAction':
      '本集播放结束后的行为：autoNext 自动倒计时并播放下一话；loop 从头循环播放；pause 停留在本集，不再自动跳转；exitPlayer 自动返回视频列表或上一页。',
  'player.precacheBufferSizeMb':
      '播放预缓存的大小，单位 MB，范围 4–512，默认 32。只对 Media Kit（libmpv）内核提供；修改后重新打开视频生效。',
  'player.precacheBufferDurationSeconds':
      '播放预缓存的时长，单位秒，范围 1–120，默认 4。只对 MDK 内核提供，设置的是缓冲区间的上限（下限固定 1 秒）。',
  'player.volumeBoost':
      '音量增强倍数，范围 1–2，1 表示不增强。实际送给内核的音量是“播放音量乘以该倍数”，与 player.volume 独立。只对 MDK 和 Media Kit 内核有效，其他内核固定按 1。',
  'player.videoAspectMode':
      '视频画面在窗口里的适配方式：contain 完整显示，保持比例，留黑边；cover 铺满并裁掉超出部分；fill 拉伸铺满，不保持比例；fitWidth 宽度铺满、高度按比例；fitHeight 高度铺满、宽度按比例；none 按视频原始像素尺寸显示；scaleDown 同 none，但超出窗口时缩小到放得下；ratio16x9 和 ratio4x3 强制按 16:9、4:3 显示。截图裁黑边使用同一套布局。',

  // ---- 截图 ----
  'player.screenshotSaveTarget':
      '截图的默认保存位置：ask 每次询问；photos 直接存入相册；file 直接存为文件（默认）。',
  'player.screenshotQuality':
      '截图的 JPEG 质量档：standard 标准（JPEG 70，体积最小）、high 高清（85）、ultra 超清（92，默认）、max 极致（100，接近无损）。只在 player.screenshotFormat 为 jpeg 时起作用，PNG 无损。',
  'player.screenshotFormat':
      '截图的文件格式：jpeg（体积较小，质量由 screenshotQuality 决定，默认）或 png（无损）。',
  'player.screenshotCropLetterbox':
      '截图时裁掉视频画面之外的上下、左右黑边，按播放器同一套适配布局计算可见区域。Erika 内核的截图本来就是不带黑边的原始视频帧。默认开启。',
  'player.screenshotDirectory':
      '截图保存目录；空字符串恢复应用的默认目录。路径须属于已授权的文件范围。',
  'player.screenshotIncludeDanmaku':
      '截图时保留显示中的弹幕层；关闭则不叠加当前弹幕。Erika 原生弹幕不在截图中，即使开启此项也不包含；截图没有弹幕不能据此判断轨道未加载或屏幕上不可见。默认开启。',
  'player.screenshotIncludeSubtitles':
      '截图时叠加内嵌和外挂字幕；关闭则不叠加。Erika 内核的截图是原始视频帧，不含字幕，此项在 Erika 下不起作用。默认开启。',

  // ---- 外部播放器（桌面端） ----
  'player.externalEnabled':
      '播放视频时改用外部播放器。启用前沿用 Classic 自动检测 mpv；未检测到且未配置路径时打开用户选择器，取消则失败并保持关闭。只在桌面端提供，默认关闭。',
  'player.externalPath':
      '外部播放器程序的绝对路径；可使用媒体目录外已安装的程序，或调用 playback.external_player_path 由用户选择/检测 mpv。空字符串清除。仅在 player.externalEnabled 为 true 时使用。',
  'player.externalType':
      '外部播放器的类型，决定如何调用它：unset 未设置、mpv、mpvNet、potPlayer、vlc、generic（其他/通用）。未保存过时按 player.externalPath 的程序名自动识别。弹幕外挂和弹幕控制台只支持 mpv、mpv.net 和 Windows 的 PotPlayer。',
  'player.externalDanmakuOverlay':
      '用外部播放器播放时，把弹幕转成 ASS 字幕注入外部播放器。支持 mpv、mpv.net 和 Windows 的 PotPlayer。默认开启；仅在 player.externalEnabled 为 true 时使用。',
  'player.externalAutoSwitchToDanmakuConsole':
      '开始外部播放后，主程序自动切换到弹幕控制台页面。弹幕控制台只支持 mpv 和 Windows 的 PotPlayer。默认开启；仅在 player.externalEnabled 为 true 时使用。',
  'player.externalShrinkWindow':
      '外部播放期间把 NipaPlay 窗口缩小到当前屏幕一半宽度，播放结束后自动恢复。默认关闭；仅在 player.externalEnabled 为 true 时使用。',
  'player.externalConsoleWindowMode':
      '弹幕控制台使用独立窗口：不再显示控制台 Tab，左侧控制面板使用竖屏窗口，并可唤出单独的弹幕列表窗口；外部播放开始后直接打开控制台窗口。目前仅支持 Linux 和 macOS。关闭时会关闭已打开的控制台窗口。默认关闭；仅在 player.externalEnabled 为 true 时使用。',

  // ---- 速度与跳转 ----
  'playback.rate':
      '播放速度倍率，1.0 为原速，范围 0.01–5.0；设置后立即作用于正在播放的视频。长按倍速（seek.speedBoostRate）生效期间，播放器实际按长按倍率运行，此值保持不变。',
  'seek.stepSeconds':
      '快进、快退按钮和方向键每次跳转的秒数。下限是一帧的时长（按视频帧率，默认按 24 帧算约 0.0417 秒），上限是当前视频的总时长（视频时长未知时为 600）；设置时会被限制在这个范围内。Classic 设置页是一组预设档位加“1 帧”。',
  'seek.speedBoostRate':
      '长按快进手势时临时切换到的播放速度倍率，范围 0.01–5.0，默认 2.0；松手后恢复原速。Classic 设置页提供 1.25、1.5、2、2.5、3、4、5 倍几档。',
  'seek.skipSeconds':
      '播放器左上角“跳过”按钮和对应快捷键向前跳过的秒数，范围 10–600，默认 90；Classic 界面以 10 秒为一档。',

  // ---- 弹幕：加载与匹配 ----
  'danmaku.convertToSimplified':
      '把繁体中文弹幕转换为简体显示。默认值随语言：系统语言不是繁体中文时默认开启。',
  'danmaku.autoMatchFirstSearchResultOnHashFail':
      '文件哈希匹配弹幕失败时，默认用文件名搜索的第一个结果自动匹配；关闭后改为弹出搜索弹幕菜单让用户选。默认开启。',
  'danmaku.autoLoadStrategy':
      '播放时自动加载弹幕的来源：remoteAndLocal（默认）自动加载远程弹幕，同时叠加视频同目录下同名的 .xml 或 .json 弹幕文件；remote 只自动识别并加载弹弹play 网络弹幕；local 只加载视频同目录下同名的 .xml 或 .json 文件。是否完全不自动加载由 danmaku.skipMatching 决定。',
  'danmaku.skipMatching':
      '开启后，播放任何来源的视频时都不会自动识别、加载弹幕或弹出匹配窗口；仍可从播放器弹幕菜单手动匹配。默认关闭。',
  'danmaku.rememberOffset':
      '切换视频时保留当前的手动弹幕偏移（danmaku.manualOffset）；自动匹配得到的偏移仍会重置。Classic 设置页名称：记忆弹幕偏移。默认关闭。',

  // ---- 弹幕：渲染引擎 ----
  'danmaku.renderEngine':
      '弹幕渲染引擎：cpu 用 Flutter Widget 绘制，兼容性好，弹幕量大时低端设备可能卡顿；gpu 自定义着色器加字体图集（实验性）；canvas 用 Canvas 绘制（实验性，来自 Kazumi 的开发者）；nipaplayNext 是 CPU 与 Canvas 两者优点的结合；next2 是 Next2 弹幕逻辑加 Rust 渲染；dfmPlus 是移植自 B 站 DanmakuFlameMaster 的 DFM+，Rust 计算加 GPU 渲染。next2 和 dfmPlus 只在支持 Rust 弹幕内核的平台可选。默认：支持 Rust 弹幕内核且不是启用 NVIDIA 图形栈的 Linux 时为 dfmPlus，否则为 nipaplayNext。Erika 内核自带原生弹幕，不使用这里选的引擎；danmaku.pluginRenderer 非空时由插件渲染器接管。',
  'danmaku.nextPlusPlusEnabled':
      'Next++ 激进优化引擎：开启后 NipaPlay Next 引擎使用 Next++ 优化路径，关闭则回到 Next 原始引擎路径。只在 danmaku.renderEngine 为 nipaplayNext 且没有启用插件渲染器时有意义。默认关闭。',
  'danmaku.pluginRenderer':
      '已安装插件提供的 WebView 弹幕渲染器的 id；空字符串表示不用插件渲染器，使用 danmaku.renderEngine 选的引擎。可选值是当前已安装并可用的渲染器。',
  'danmaku.supersample':
      '弹幕超采样渲染的像素密度倍数：0 关闭，原始分辨率，GPU 负担最低；1.5 为 1.5 倍像素密度，平衡清晰度与性能；2 为 2 倍，文字最清晰，GPU 负担较高。只接受这三个值。只对 next2 和 dfmPlus 引擎提供。默认值：iPad 1.5，平板和低 DPI（像素比小于 2）桌面 2，其他 0。',

  // ---- 弹幕：外观与布局 ----
  'danmaku.visible':
      '弹幕显示开关，也作用于 Erika 原生弹幕；值为 true 不代表当前时刻屏幕上已有弹幕。轨道加载、时间位置与过滤仍影响实际显示。',
  'danmaku.showDensityChart':
      '在播放器底部显示弹幕密度曲线。Classic 设置页名称：弹幕密度曲线（外观页）。默认关闭。',
  'danmaku.randomColor':
      '忽略弹幕原始颜色，按发送弹幕的预设色板随机分配颜色（同一条弹幕每次分配结果相同）。默认关闭。',
  'danmaku.stacking':
      '允许多条弹幕重叠显示，适合弹幕密集场景。CPU、GPU、Canvas、Next2、DFM+、插件渲染器和 Erika 读取此值；NipaPlay Next 引擎固定不堆叠。Classic 只在 CPU、GPU 引擎和 Erika 内核下显示这个开关。默认关闭。',
  'danmaku.merge':
      '把内容相同的弹幕合并为一条显示。Classic 在 Canvas 引擎下不显示这个开关。默认关闭。',
  'danmaku.blockTop': '不显示顶部固定弹幕。默认关闭。',
  'danmaku.blockBottom': '不显示底部固定弹幕。默认关闭。',
  'danmaku.blockScroll': '不显示从右向左滚动的弹幕。默认关闭。',
  'danmaku.timelineEnabled':
      '时间轴告知弹幕：在视频播放到特定进度（25%、50%、75%、90%）时显示一条弹幕提示。默认开启。',
  'danmaku.opacity':
      '弹幕不透明度，0–1：0 完全透明，1 完全不透明，默认 1。Classic 界面按百分比显示这个值。注意 Flutter 绘制的引擎（CPU、GPU、Canvas、NipaPlay Next、Next2、DFM+ 和插件渲染器）实际使用的是该值的平方，所以 0.7 实际渲染为 0.49；Erika 内核原生弹幕收到的是原值。插件渲染器启用 Titan 设置时改读 danmaku.titan.opacity。',
  'danmaku.fontSize':
      '弹幕字号，单位像素。0 表示使用设备默认字号（手机 20，其他设备 30），否则取 12–60。保存后用于后续播放。Classic 界面滑块范围 12–60，步长 0.5；插件渲染器启用 Titan 设置时改读 danmaku.titan.fontSize。',
  'danmaku.speedMultiplier':
      '滚动弹幕速度倍率，范围 0.5–2，1 为原速。滚动弹幕的基准时长是 10 秒除以该倍率：2 是 5 秒（更快），0.5 是 20 秒（更慢）；这个时长同时传给各弹幕引擎。',
  'danmaku.displayArea':
      '弹幕轨道占视频画面高度的比例，从画面顶部向下算：1 是整个画面高度，0.5 是上半屏，0.25 是上四分之一。轨道数约等于“画面高度乘以该比例”除以一条弹幕的轨道高度（字号加轨道间距），不足一条时仍保留 1 条轨道；取 0 时只有单行。Classic 界面只给六档：0 单行显示、0.125 即 1/8 屏幕、0.25 即 1/4 屏幕、0.33 即 1/3 屏幕、0.67 即 2/3 屏幕、1.0 全屏。Classic 显示当前值时会吸附到最近的一档（0.7 显示为 2/3 屏幕），但引擎按设置的原值使用，其他数值同样可用。DFM+ 的滚动弹幕最多只用到画面 0.75 的高度，超出部分只给顶部和底部的固定弹幕；NipaPlay Next、Next2、DFM+ 在取 1.0 时会少留一条轨道作底部边距。',
  'danmaku.trackGap':
      '弹幕轨道间距，以一条弹幕自身高度的倍数计：轨道高度 = 弹幕高度 ×（1 + 该值），0.15 即在弹幕上下之间多留 15% 的空隙。范围 0–2，默认 0.15；Classic 界面滑块范围 0–0.5，以百分比显示。增大减少重叠，减小同屏能显示更多弹幕。只对 DFM+ 引擎和 Erika 内核有效，Classic 在其他引擎下不显示；插件渲染器的 Titan 设置另有 danmaku.titan.trackGap。',
  'danmaku.outlineWidth':
      '弹幕描边档位，只有三档：0 无描边，1 细边，2 粗边。保存时任何正数会被归入 1 或 2（小于 1.5 归 1，其余归 2），不是像素宽度。设为 0 会把 danmaku.outlineStyle 同时置为 none；从 0 改为正数时，若描边样式是 none 则恢复为平台默认样式（手机 stroke，其他 uniform）。默认 2（tvOS 为 1）。Classic 设置页名称：弹幕描边粗细，说明“0 为无描边，1 为细边，2 为原来的粗边”；播放器弹幕菜单在 Next2、DFM+ 和 Erika 下用这个 0/1/2 滑块，其他引擎改用 outlineStyle 选项。',
  'danmaku.outlineStyle':
      '弹幕描边样式：none 无描边；stroke 标准描边；uniform 均匀描边。默认手机 stroke，其他 uniform。设为 none 会把 danmaku.outlineWidth 置 0；从 none 改成其他样式时，若 outlineWidth 为 0 则恢复为 2。Classic 界面在 Next2、DFM+ 和 Erika 之外的引擎下用这个选项，这些引擎改用 outlineWidth 的 0/1/2 档。',
  'danmaku.shadowStyle':
      '弹幕阴影样式：none 无阴影；soft 柔和阴影；medium 标准阴影；strong 增强阴影。默认手机 none，其他 strong。Classic 在 Next2、DFM+ 引擎和 Erika 内核下只有开/关两档：开对应 strong，关对应 none；Erika 内核下 Classic 不显示阴影选项，但会把此值传给内核。',
  'danmaku.fontFamily':
      '弹幕使用的字体族名，空字符串使用系统默认字体；需与系统字体或已导入的字体名一致。恢复默认字体（danmaku.fontFilePath 设为空）会同时清空这个值。插件渲染器启用 Titan 设置时改读 danmaku.titan.fontFamily。',
  'danmaku.fontFilePath':
      '弹幕字体文件路径，空字符串恢复系统默认字体（同时清空 danmaku.fontFamily）；路径须属于已授权的文件范围。字体文件会通过现有导入流程保存为应用内副本，支持 ttf、otf、ttc、otc。',
  'danmaku.blockWords':
      '弹幕屏蔽词列表：弹幕内容包含某个词，或被某条正则命中，就不显示。正则规则写成“规则名称/表达式/”的形式（中间包含 / 且以 / 结尾）。Classic 添加时支持逗号分隔批量输入，并拒绝空词和重复词。',
  'danmaku.manualOffset':
      '当前会话的弹幕手动偏移，单位秒，不增加持久偏好。渲染时弹幕时间 = 视频播放时间 + 偏移，所以正值让弹幕提前出现，负值让弹幕延后出现（与 Classic 弹幕偏移菜单“弹幕将提前 N 秒显示”一致；Classic 设置页副标题的“负值提前，正值延后”与此相反）。Classic 设置页滑块范围 ±10 秒。切换视频是否保留由 rememberOffset 控制。',

  // ---- 弹幕：防剧透 AI ----
  'danmaku.spoilerPreventionEnabled':
      '使用用户已配置的 AI 接口识别并屏蔽疑似剧透的弹幕，加载弹幕后执行；未完成接口配置（接口 URL、API Key、模型）时不能启用。默认关闭。',
  'danmaku.spoilerAiApiUrl':
      '防剧透 AI 接口的 URL；格式由 danmaku.spoilerAiApiFormat 决定。',
  'danmaku.spoilerAiApiFormat':
      '防剧透 AI 接口的格式：openai 为 OpenAI 兼容接口，gemini 为 Gemini 接口。',
  'danmaku.spoilerAiModel':
      '防剧透 AI 使用的模型名，默认 gpt-5。',
  'danmaku.spoilerAiTemperature':
      '防剧透 AI 请求的采样温度，范围 0–2，默认 0.5；越大输出越随机，0 最确定。',
  'danmaku.spoilerAiDebugPrintResponse':
      '把防剧透 AI 的响应原文、提取出的文本和解析结果打印到调试日志（长度会被截断）。只影响日志，不影响屏蔽结果。默认关闭。',

  // ---- 字幕 ----
  'subtitle.scale':
      '字幕缩放倍率，范围 0.5–2.5，1 为原大小；Classic 界面以百分比显示（100% 即 1），说明为“缩放 libass 字幕大小”。Media Kit 和 Erika 内核按此值设置 sub-scale，MDK 内核设置 subtitle.scale 属性；Next 的 effective 只认定 Media Kit 和 Erika 下有效（其他内核报 kernel_unsupported），MDK 下是否真有缩放效果未能从代码确定。外挂叠层字幕的大小用 subtitle.srtScale。',
  'subtitle.srtScale':
      '由应用叠层绘制的外挂字幕（srt、vtt、ass、ssa）的缩放倍率，范围 0.5–2.5，1 为默认大小。基准字号是叠层宽度的 3%（限制在 18–42 像素），再乘以该倍率，最终限制在 14–72 像素。不影响内核和内嵌字幕，它们用 subtitle.scale。',
  'subtitle.delaySeconds':
      '字幕时轴偏移（秒）；正值延后，负值提前。作用于内核字幕（mpv 的 sub-delay）。SRT 独立偏移沿用当前视频时长限制。',
  'subtitle.srtDelaySeconds':
      '由应用叠层绘制的外挂字幕（SRT 等）的独立时轴偏移（秒）；正值延后，负值提前，范围受当前视频时长限制。不影响内核字幕，它们用 subtitle.delaySeconds。',
  'subtitle.position':
      '内嵌和内核字幕的垂直位置，0–100：0 在画面顶部，100 在画面底部（默认）。对应 mpv 的 sub-pos。外挂叠层字幕由用户在画面上长按拖动逐条定位，这个值不覆盖它们。',
  'subtitle.marginX':
      '内嵌和内核字幕距左右边缘的距离，单位像素，保存时取整。Classic 界面范围 0–200；mpv 的 sub-margin-x 在 Media Kit 下只接受 0–300。外挂叠层字幕不使用。',
  'subtitle.marginY':
      '内嵌和内核字幕距上下边缘的距离，单位像素，保存时取整。Classic 界面范围 0–200；mpv 的 sub-margin-y 在 Media Kit 下只接受 0–300。外挂叠层字幕不使用。',
  'subtitle.opacity':
      '内嵌和内核字幕的整体不透明度，0–1：0 完全透明，1 完全不透明（默认）。换算成 0–255 设给 mpv 的 sub-opacity。',
  'subtitle.borderSize':
      '内嵌和内核字幕的描边粗细（mpv 的 sub-border-size），0–10，默认 3；0 无描边。',
  'subtitle.shadowOffset':
      '内嵌和内核字幕的阴影偏移（mpv 的 sub-shadow-offset），0–10，默认 0；0 无阴影。',
  'subtitle.alignX':
      '内嵌和内核字幕的水平对齐：left 左对齐、center 居中（默认）、right 右对齐。',
  'subtitle.alignY':
      '内嵌和内核字幕的垂直对齐：top 顶部、center 垂直居中、bottom 底部（默认）。',
  'subtitle.overrideMode':
      'ASS 字幕自带样式的接管策略（mpv 的 sub-ass-override）：auto 自动，字幕缩放不是 1 时按 scale，否则保持原样；none 保持原样；scale 仅缩放；force 自定义样式（Classic 说明：外挂字幕应用所选字体，内嵌字幕强制覆盖 ASS 自带样式）。字体（subtitle.fontName、subtitle.fontDir）只在 force 下生效，其他模式会清空自定义字体目录。',
  'subtitle.bold': '内嵌和内核字幕使用粗体（mpv 的 sub-bold）。默认关闭。',
  'subtitle.italic': '内嵌和内核字幕使用斜体（mpv 的 sub-italic）。默认关闭。',
  'subtitle.color':
      '内嵌和内核字幕的文字颜色，#AARRGGBB 格式，默认 #FFFFFFFF（不透明白）。不影响外挂叠层字幕，它们用 subtitle.externalColor。',
  'subtitle.borderColor':
      '内嵌和内核字幕的描边颜色，#AARRGGBB 格式，默认 #FF000000（不透明黑）。',
  'subtitle.shadowColor':
      '内嵌和内核字幕的阴影颜色，#AARRGGBB 格式，默认 #FF000000（不透明黑）。',
  'subtitle.externalColor':
      '由应用叠层绘制的外挂字幕（SRT 等）的文字颜色，#AARRGGBB 格式，默认 #FFFFFFFF。不影响内嵌和内核字幕，它们用 subtitle.color。',
  'subtitle.fontName':
      '内嵌和内核字幕使用的字体名，空字符串为默认；需与系统字体或已导入的字体名一致。只在 subtitle.overrideMode 为 force 时生效。',
  'subtitle.externalFontName':
      '由应用叠层绘制的外挂字幕（SRT 等）使用的字体名，空字符串为默认。独立于 subtitle.fontName，不影响内嵌字幕。',
  'subtitle.fontDir':
      '字幕字体目录（mpv 的 sub-fonts-dir）；路径须属于已授权的文件范围。字体文件会通过现有导入流程保存为应用内副本。只在 subtitle.overrideMode 为 force 时生效；应用也会优先使用视频同目录的 fonts 文件夹和应用内的 subtitle_fonts 字体库。',

  // ---- 插件渲染器 Titan 参数（仅当前启用的插件弹幕渲染器声明使用 Titan 设置时可见） ----
  'danmaku.titan.opacity':
      'Titan 弹幕不透明度，0.2–1，默认 0.85。只影响使用 Titan 设置的插件渲染器，不改变其他引擎的 danmaku.opacity。',
  'danmaku.titan.fontSize':
      'Titan 字号倍率，0.5–2，默认 1；是倍率，不是像素。只影响 Titan 渲染器，不改变 danmaku.fontSize。',
  'danmaku.titan.bold': 'Titan 弹幕使用 Titan 原生粗体样式，默认开启。',
  'danmaku.titan.fontBorder':
      'Titan 描边类型（引擎的 fontBorder）：0 重墨，1 描边，2 45° 投影。默认 0。',
  'danmaku.titan.fontFamily':
      'Titan 弹幕字体（CSS font-family 字符串）。Classic 提供黑体、简体系统字体、宋体、新宋体、仿宋、微软雅黑等预设；字体未安装时 WebView 会回退到简体中文系统字体。',
  'danmaku.titan.speedPlus':
      'Titan 滚动速度倍率（引擎的 speedPlus），0.25–3，默认 1；越大越快。不改变其他引擎的 danmaku.speedMultiplier。',
  'danmaku.titan.density':
      'Titan 弹幕密度，0.1–1，默认 1，限制同屏轨道占用的比例；越小弹幕越稀。',
  'danmaku.titan.duration':
      'Titan 基准时长，单位秒，2–12，默认 4.5，是滚动弹幕的基础存活时间。',
  'danmaku.titan.limit':
      'Titan 同屏弹幕上限，0–1000，默认 300；0 表示由引擎决定。',
  'danmaku.titan.trackGap':
      'Titan 弹幕轨道间距，0–0.5，Classic 界面以百分比显示；默认手机 0.15，其他设备 0。增大减少重叠，减小同屏能显示更多弹幕。',
  'danmaku.titan.preventShade':
      'Titan 防挡字幕：避免弹幕覆盖画面底部的字幕区域。默认关闭。',
  'danmaku.titan.offsetTop':
      'Titan 顶部弹幕轨道的偏移，单位像素，-100–100，默认 3。',
  'danmaku.titan.offsetBottom':
      'Titan 底部弹幕轨道的偏移，单位像素，-100–100，默认 0。',
  'danmaku.titan.maxLength':
      'Titan 单条弹幕文字的最大长度，0–1000，默认 50；0 表示不限制。Classic 界面滑块范围 0–200。',
  'danmaku.titan.isRecyclingDom':
      'Titan 复用已经离屏的弹幕 DOM 节点，默认开启。',
  'danmaku.titan.isRecyclingModel':
      'Titan 复用引擎内部的弹幕模型，默认关闭。',
  'danmaku.titan.forbidShrinkState':
      'Titan 禁止缩小：轨道拥挤时不自动缩小弹幕文字，默认开启。',
};

/// classic_settings.dart 里注册的设置（不含已在注册处写了说明的）。
const classicSettingDescriptions = <String, String>{
  // ---- 外观 ----
  'appearance.showAnimeCardSummary':
      '番剧卡片上显示简介；关闭后只显示封面和标题。默认开启。',
  'appearance.showQuarterlyAnimeReview':
      '首页在季度末和下个月前 7 天显示“新番回顾”。默认开启。',
  'appearance.showMediaLibraryNewBadge':
      '在有新内容的番剧卡片上显示 NEW 标识。默认开启。',
  'appearance.diffuseLowResolutionPosters':
      '首页低分辨率的推荐海报强烈模糊，形成晕染效果。默认开启。',
  'appearance.showHomeHeroBanner':
      '主页顶部左侧的大幅推荐轮播横幅。默认开启。',
  'appearance.showHomeHeroSideCardTop':
      '主页顶部右上角的推荐小卡片，仅桌面和平板布局有。默认开启。',
  'appearance.showHomeHeroSideCardBottom':
      '主页顶部右下角的推荐小卡片，仅桌面和平板布局有。默认开启。',
  'appearance.accentColor':
      '应用界面的强调色预设：rose 绯红（默认）、blue 蓝色、green 荧绿。',
  'appearance.folderNameDisplayMode':
      '媒体库管理里过长目录名的显示方式：ellipsis 省略号截断（默认）、multiline 多行完整显示。',
  'appearance.windowDisplayMode':
      'NipaPlay Window 控件（虚拟窗口）的显示范围：windowed 窗口化，居中弹窗、四周留有较大空白；filledScreen 铺满屏幕，贴近屏幕边缘、只保留少量间距。默认平板 filledScreen，其他 windowed。',
  'appearance.uiScale':
      '界面整体缩放倍率，范围 0.5–1.3，步长 0.05，1 为原大小，Classic 界面显示为 x1.00。默认电视和平板 1.2，其他 1.0；支持自动缩放的设备上，手动调节会关闭自动适配（appearance.automaticUiScale）。',
  'appearance.automaticUiScale':
      '启动时根据显示分辨率和系统缩放自动选择界面大小；开启时 appearance.uiScale 读出的是自动算出的值，手动调节界面缩放滑块会关闭它。仅在支持自动缩放的设备（Android TV）上提供，默认开启。',
  'appearance.themeMode':
      '应用界面的颜色主题：system 跟随系统、light 浅色、dark 深色。默认电视 dark，其他 system。',
  'appearance.backgroundImageMode':
      '应用主界面的背景图像来源，取值是 Classic 的中文名：“看板娘”、“看板娘2”（内置图）、“关闭”（默认）、“自定义”（使用 appearance.customBackgroundPath 指向的图片）。',
  'appearance.customBackgroundPath':
      '背景图像模式为“自定义”时使用的图片路径；assets/ 开头的是内置资源，其他路径须属于已授权的文件范围。默认是内置图（桌面和平板 main_image.png，手机 main_image_mobile.png）。',
  'appearance.backgroundRenderMode':
      '背景颜色与背景图片的合成方式：opacity 不透明度，soft_light 柔光。背景图像为“关闭”时 Classic 不显示这个选项。',
  'appearance.backgroundOverlayOpacity':
      '覆盖在背景图像上的背景颜色的强度，0–1：0 不叠加，1 完全覆盖，默认 0.3。背景图像为“关闭”时 Classic 不显示这个选项。',
  'appearance.blurPower':
      '背景毛玻璃的模糊强度，只接受 Classic 的预设档：0 无、5 轻微、15 中等、25 高、50 超级、100 梦幻；电视上只有到 25 的档。默认 0。数值越大，每帧重绘的开销越高。',
  'appearance.homeSectionsOrder':
      '首页各分区的显示顺序，是分区 id 的完整排列，每个分区恰好出现一次：today_series 今日新番、trending 排行榜、random_recommendations 随机推荐、continue_watching 继续播放、remote_libraries 远程媒体库、local_library 本地媒体库。',
  'appearance.homeSectionsDisabled':
      '在首页隐藏的分区 id 列表（id 同 appearance.homeSectionsOrder）；不在列表里的分区显示。默认为空，即全部显示。',

  // ---- 语言与通用 ----
  'language.mode':
      '应用界面语言：auto 跟随系统（默认）、simplified 简体中文、traditional 繁体中文、english 英文。',
  'general.desktopExitBehavior':
      '点击桌面窗口关闭按钮时的行为：askEveryTime 每次询问（默认）、minimizeToTrayOrTaskbar 最小化到系统托盘（或任务栏）、closePlayer 直接退出。只在桌面端提供。',
  'general.startupWindowState':
      '桌面端启动时的窗口状态：windowed 窗口化、maximized 最大化（默认）。',
  'general.startupWindowPosition':
      '桌面端窗口化启动时窗口在屏幕上的位置：topLeft 左上角、topRight 右上角、center 居中（默认）、bottomLeft 左下角、bottomRight 右下角。',
  'general.startupWindowWidth':
      '桌面端启动时的窗口宽度，单位像素，不小于 600，默认 1280。Classic 预设：紧凑 960×600、标准 1280×720、宽屏 1440×900、超大 1920×1080，也可自定义。',
  'general.startupWindowHeight':
      '桌面端启动时的窗口高度，单位像素，不小于 400，默认 720。Classic 预设：紧凑 960×600、标准 1280×720、宽屏 1440×900、超大 1920×1080，也可自定义。',
  'general.pictureInPicturePosition':
      '桌面端进入画中画时窗口停靠在当前屏幕的位置：topLeft 左上角、topRight 右上角（默认）、bottomLeft 左下角、bottomRight 右下角。保存时会立即把画中画窗口移到该位置。',
  'general.autoCheckUpdates':
      '后台自动检测应用更新；关闭后只能手动检测。默认开启。Classic 设置页名称：自动检测更新（关于页）。',

  // ---- 诊断与实验 ----
  'diagnostics.showSystemResources':
      '在界面右上角显示 CPU、内存和帧率信息。默认关闭。',
  'diagnostics.collectLogs':
      '收集应用的所有打印输出，用于调试和问题诊断；开启时立即开始收集，关闭时立即停止。Classic 设置页名称：调试日志收集。默认开启。',
  'diagnostics.fileLog':
      '把日志每 1 秒写入磁盘，保留最近 5 份日志文件；开启时立即开始写入，关闭时立即停止。Classic 设置页名称：日志写入文件。默认开启。',
  'labs.enableErikaPlayerKernel':
      '实验开关：开启后播放器内核下拉菜单里显示 Erika（player.kernel 的 erika）。电视和 HarmonyOS 上不需要此开关。默认关闭。',
  'labs.enableImmersiveAnimeDetail':
      '实验开关：开启后桌面、平板和手机都使用新版全屏番剧详情页（Classic 实验室页名称：新版番剧卡片页面）。默认关闭。',

  // ---- WebDAV 快捷入口 ----
  'webdavQuick.showTab':
      '在底部导航栏显示 WebDAV 快捷入口 Tab，用来快速访问 WebDAV 服务器里的视频文件。默认关闭。',
  'webdavQuick.defaultServerName':
      '点击 WebDAV Tab 时默认连接的服务器名称，是“远程媒体库”设置里已添加的 WebDAV 服务器之一；空字符串表示未指定。',
  'webdavQuick.defaultDirectory':
      '点击 WebDAV Tab 时直接打开的目录路径，默认 /（根目录）。',
  'webdavQuick.sortPreset':
      'WebDAV 文件排序：default 默认（文件夹在前，各自按名称 A-Z）；name_asc 名称 A-Z（所有项目混合排序）；name_desc 名称 Z-A；modified_desc 最新修改在前；modified_asc 最旧修改在前；size_desc 文件大小从大到小；size_asc 文件大小从小到大。',
  'webdavQuick.showPathBreadcrumb':
      '在 WebDAV 页面顶部显示可点击的路径面包屑导航。默认开启。',
  'webdavQuick.autoEnterSeasonFolder':
      '打开文件夹时，自动进入名称匹配 webdavQuick.seasonFolderPattern 的子文件夹。默认关闭。',
  'webdavQuick.seasonFolderPattern':
      '自动进入 Season 文件夹时用的名称匹配模式，支持通配符：* 匹配任意字符，? 匹配单个字符。默认 Season*。',
  'webdavQuick.bgmIdQuickMatch':
      '从文件 URL 中提取 bgmid，直接获取番剧信息，跳过识别。规则由 webdavQuick.bgmIdMatchPattern 决定。默认关闭。',
  'webdavQuick.bgmIdMatchPattern':
      '提取 bgmid 的正则表达式，必须含捕获组，最后一个捕获组应为数字。默认 bgm(id)?[=-](\\d+)，可匹配 bgmid=123 或 bgm-123。',
  'webdavQuick.tmdbIdQuickMatch':
      '从文件 URL 中提取 tmdbId，通过 TMDB ID 直接获取番剧信息，跳过识别。规则由 webdavQuick.tmdbIdMatchPattern 决定。默认关闭。',
  'webdavQuick.tmdbIdMatchPattern':
      '提取 tmdbId 的正则表达式，必须含捕获组，最后一个捕获组应为数字。默认 tmdb(id)?[=-](\\d+)，可匹配 tmdbid=123 或 tmdb-123。',
  'webdavQuick.episodeOffsetEnabled':
      '匹配弹幕时自动计算跨季剧集编号偏移，修复季内编号与弹幕库绝对编号对不上的问题。默认关闭。',
  'webdavQuick.enableSearch':
      '在 WebDAV 页面显示文件搜索按钮。默认开启。',
  'webdavQuick.searchScope':
      'WebDAV 搜索范围：current_directory 仅当前目录；current_with_depth 当前目录加子目录，向下遍历 webdavQuick.searchDepthLimit 层（默认）；global 从根目录开始搜索全部。',
  'webdavQuick.searchDepthLimit':
      '搜索向下遍历的目录层数，1–10，默认 3；在搜索范围为“当前目录加子目录”或全局搜索时生效。',
  'webdavQuick.searchTargets':
      '搜索结果包含的类型，可选 folder（文件夹）和 video（视频文件），至少选一项，不重复。默认两者都包含。',
  'webdavQuick.searchTimeout':
      '搜索超时秒数，达到后停止搜索：只接受 10、30（默认）、60，0 表示无限制。',
  'webdavQuick.searchRequestInterval':
      '搜索时两次请求之间的间隔，单位毫秒，0–1000，默认 100；防止请求过快被服务器限制，0 表示无延迟。',
  'webdavQuick.searchMaxResults':
      '搜索结果的数量上限，50–2000，默认 500；达到上限时自动停止搜索。',

  // ---- 首页 ----
  'appearance.quarterlyReviewSort':
      '首页“新番回顾”的排序：airDate 季度日期（默认）、commentNewest 评论时间新到旧、commentOldest 评论时间旧到新、ratingHigh 用户评分高到低、ratingLow 用户评分低到高。',
};

/// system_settings.dart 里注册处没有写说明的调试项。
const systemSettingDescriptions = <String, String>{
  'diagnostics.canvasDanmakuCollisionBoxes':
      '开发者调试项，只在调试构建里注册：为 Canvas 弹幕引擎画碰撞框。未能从代码确定：Canvas 渲染器里没有找到读取这个开关的位置。默认关闭。',
  'diagnostics.canvasDanmakuTrackNumbers':
      '开发者调试项，只在调试构建里注册：为 Canvas 弹幕引擎显示轨道号。未能从代码确定：Canvas 渲染器里没有找到读取这个开关的位置。默认关闭。',
  'diagnostics.gpuDanmakuCollisionBoxes':
      '开发者调试项，只在调试构建里注册：为 GPU 弹幕引擎的顶部、滚动、底部三类弹幕画出碰撞框。只在 danmaku.renderEngine 为 gpu 时看得到。默认关闭。',
  'diagnostics.gpuDanmakuTrackNumbers':
      '开发者调试项，只在调试构建里注册：为 GPU 弹幕引擎显示轨道号。只在 danmaku.renderEngine 为 gpu 时看得到。默认关闭。',
};
