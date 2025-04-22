Change log:

# 0.32.0

- API:
    - Add `AudioFrame` and `Player.onFrame<AudioFrame>()`. Example: [obs](https://github.com/wang-bin/obs-mdk/commit/b5027fffa08765626954af8e5ca0566416e50f38)
    - `VideoFrame.from()` can import CUDA and VAAPI resources
- **NEW: VP8/9, HEVC with Alpha support.** Maybe it's the 1st player engine supports those standard alpha videos.
    - VP8/9, HEVC alpha layer decoding for all decoders.
    - alpha layer rendering in all renderers. Alpha and base layer can be from different decoders and have different strides, and sampler types can be different.
    - `alpha=0` can disable alpha layer decoding, e.g. `player.setProperty("video.decoder", "alpha=0")`
- non-standard alpha videos whose alpha data is at bottom or right, enable via decoder property `alpha=right` or `alpha=bottom`. sw decoder or hw decoder copy mode only.
- MFT: support HEVC base layer decoding if has multiple layers(alpha and MV-HEVC). By default such bitstream is rejected by MFT
- D3D11: fix downloading from stage texture, previously may crash on amd, arm64
- CUDA:
    - Only decode base layer of has multiple layers. By default it decodes all layers(alpha and MV-HEVC).
    - Add properties `device`, `stream`, `pbo` etc. see https://github.com/wang-bin/mdk-sdk/wiki/Decoders#cuda
    - Fix a crash when destroying the last frame
- VT: `RequestedMVHEVCVideoLayerIDs` bug reported by me in 2024 is fixed in macOS 15.4, so remove workaroud for macOS 15.4+
- VAAPI: add "vpp" property, 1 to convert to rgb via vpp
- EGL:
    - Prefer storage extension instead of external image for desktop gl, supported formats is vendor dependent. Works well on raspberry pi, previously only OpenGL ES + external image is supported.
    - Fix no hdr metadata warnings in system log on android
    - Support android platform display
    - Fix HDR display if no colorspace extension(regression in 0.31.0)
    - Fix crash if no client extension(regression in 0.31.0)
- Add value "fit" to property "subtitle.size" to scale subtitle to renderer size and keep aspect ratio
- CMake: add rpath-link for linux libc++
- Load libshaderc.so instead of libshaderc-shared.so on linux
- global option videoout.hdr10_metadata=0 can disable hdr10 metadata passthru to display
- Fix old subtitle rendered if track switched
- Fix point map if render api changed(default opengl, to another)
- Don't clear render target if failed to open a decoder
- FFmpeg:
    - Add "format" option for sw decoder. used by hevc alpha, for example `format=yuva420p`
    - "sw_fallback" property applies for codecs w/o hwaccel


# 0.31.0

- API:
    - Add color space and dolby vision profile in MediaInfo
    - Add `VideoEffect::ScaleChannels` and `ShiftChannels`
    - Add `Player.subtitleText()` to get subtitle text(except bitmap subtitles) with ass style or not, even if subtitle rendering is disabled by `setProperty("subtitle", "0")`. see https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#stdstring-subtitletextdouble-time---1-int-style--0-const
- EGL:
    - Support HDR color spaces. `player.set(ColorSpaceUnknown)` will switch between HDR and SDR color space depending on current rendering video frame. Tested on android, may work on linux
    - Enable HDR10 metadata pass through, can be disabled by env var `EGL_HDR_METADATA=0`
    - Prefer rgb10a2 to avoid recreating context when switching between SDR and HDR
    - Support KHR_no_config_context to avoid recreating context when switching between SDR and HDR
- Subtitle:
    - Fix properties not applied if set before play
    - Support splitting ASS rendered rgba image into several smaller regions when possible to reduce total size and gpu bandwidth. controlled by player property `subtitle.ass.regions.max` or env `ASS_REGIONS_MAX`, value is int. use `subtitle.ass.regions.debug` or env `ASS_REGIONS_DEBUG` to visualize regions and show debug messages.
    - Keep colorspace the same as video, fix dark in bt2020 pq
    - Add player property `subtitle.scale` to scale all kind of subtitles. default is 1.0, i.e. no scale
    - Fix `subtitle.blur` is not applied because of a libass bug
    - Add player property `subtitle.size`, default value is `video` to render in video frame size, other values will render in video renderer resolution
    - Redraw subtitle if output resolution changed even if playback is paused, e.g. rendering in renderer resolution, and resize the renderer
    - Redraw subtitle for any subtitle property change even if playback is paused.
    - Render earlier
    - Fix dead lock
    - Fix unexpected null texture for some timestamp values and blinking
    - Set ass storage size
- Dolby vision: Fix shader error if yuv sampler is used for MediaCodec decoder
- GL: add `glFinish()` before context destroyed
- D3D11: Improve UMA support check. UMA optimized texture download. can be disabled by env `GPU_OPTIMAL_DOWNLOAD=0`
- DXGI: Use the 1st screen's HDR capability
- Metal: Fix rendering mutiple overlayes
- MFT: return error if output type is not supported
- Fix wrong start time if `record()` multiple times.
- Fix buffered packets out of range of the value set by `setBufferRange()`
- Fix audio not decoded after seek if paused and result in a/v desync(apple only).
- Fix seek(if not started) callback may be called twice.
- Fix global subtitle options not applied, regression in 0.30.1
- FFmpeg:
    - Support webvtt in mkv. Patch is from avbuild, not merged by upstream.
    - Workaround aac packets from rtsp have no keyframe if ffmpeg > 7.1


# 0.30.1

- Fix a crash in audio renderer if get delay
- renderVideo() before the 1st frame will clear render target with background color. useful if render target content is undefined
- Fix some global options not applied immediately
- FFmpeg: prefer new avcodec_get_supported_config()


# 0.30.0

- API:
    - Add `Player.appendBuffer()` to play streams with user provided data, for example data is from [websocket](https://github.com/wang-bin/mdk-examples/blob/master/Native/stream.cpp). media protocol is `stream`, i.e. `player.setMedia("stream:empty_or_any_string")`. `setTimeout()` can abort current playback if timedout to read data from user.
- Plain text subtitle(srt for example) style can be changed by user via [subtitle properties](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#subtitle-properties)
- Multi channels audio rendering, no downmix to stereo
- Support dolby vision in mpeg ts
- PulseAudio is the default audio render for linux
- Improve audio renderer delay and AV sync
- VT: Fix hardware decoder disabled if hvcC has no PS NALUs
- D3D11:
    - Fix UMA check if run x64 on arm64 and failed to create textures
    - Disable cross context 0-copy for AMD gpus to avoid corrupt result on many gpus
    - Set usage for swapchain, fix back buffer RTV create error on some win7 devices
- VAAPI:
    - Map YUYV fourcc, fix jpeg yuv 422 rendering
    - Convert to RGB with VPP if DRM to EGLImage is not possible(desktop gl + external only formats)
- DRM Prime:
    - Error if no OpenGL ES2/3 context for external only formats, then VAAPI can fallback to suboptimal rendering instead of blank
    - Map more formats
- Player property "audio.tracks", "video.tracks" and "subtitle.tracks" is same as `setActiveTracks()`, value is a int list string, e.g. `"0,1"`
- Reset more callbacks before deleting player object to simplify user code
- Fix undefined symbol on wayland < 1.10, compatible with more linux distributions, e.g. ubuntu 14.04
- More packed yuv formats
- MFT: fix d3d9 not tried if d3d11 is not supported
- Fix null callback invoked if reset by user
- Will try to load Ass.framework on apple OS except macOS, to be compatible with media-kit's frameworks
- FFmpeg: Fix wromg abi version if avfilter is disabled when swresample is loaded and crash, e.g. qt6's ffmpeg dlls
- Add nvjpeg2000 plugin for windows x64, requires cudart64_12.dll and nvjpeg2k_0.dll
- Compatible with libc++20


# 0.29.1

- Android 64bit is built with 16KB page size support
- Supprt GL_EXT_EGL_image_storage for drm, via global option "eglimage.storage=1"
- VAAPI: prefer x11 display to support both EGL and GLX
- Add privacy manifest for apple platforms
- Improve demuxer cache
- Enable http reconnect
- Fix OpenGL symbols not resolved on android 15 emulator
- Fix snapshot in OpenGL renderers
- Fix snapshot callback not invoked if failed
- Fix muxer write after close
- Fix a decoder crash when stopping playback
- Fix waitFor(State::Stopped)
- Stop demuxer immediately if io is aborted.
- Apply ffmpeg muxer options
- Prefer ffmpeg dynamic library even if statically linked. mainly used by iOS user provided FFmpeg.framework


# 0.29.0

- Support demuxer cache for http(s), can be enabled via `player.setProperty("demux.buffer.ranges", "8"/*or other positive int*/)`. `{count, "cache.ranges"}` event will be triggered when cached time ranges are created, dropped(via LRU cache) or merged. Other protocols can be enabled via player property `player.setProperty("demux.buffer.ranges", "http,https,proto1,proto2");`.
- Add `Player.bufferedTimeRanges()`
- Dolby vision: support reading metadata from av1 in all decoders, previously only supported by ffmpeg hwaccels and software decoder.
- Support pause/resume rtsp stream in `Player.set(State)`. Enable via `player.setProperty("reader.pause", "1");`.
- Record video from non-key frame if property "reader.starts_with_key" is "0"
- Support [nvJPEG2000 as a plugin](https://github.com/wang-bin/mdk-nvjp2k/actions)
- Support planar xyz format, produced by nvJPEG2000
- Support p012, p212, p412, can be produced by VT decoder(can be tested with VT:fourcc=tv20)
- OpenGL:
    - Detect(guess) invalid foreign context, usually in old OSes(ubuntu 20.04) and with `GLRenderAPI.getProcAddress` set by user.
    - Fix blank display if failed update textures
- D3D11: fix crash if decoder and renderer adapters are different
- Metal:
    - Set layer scale, fix low resolution
    - Build highest shader version
- VT: support ProRes without fourcc
- VAAPI:
    - Prefer drm display over x11, less errors, better performance
    - Fix upload unmapped host memory crash
- Fix wrong channels in recorded pcm
- Fix prepare callback not invoked if decoder changed
- Fix rgb48be rendering
- FFmpeg
    - Improve abi compatibility, found in x86 32bit ffmpeg 4.x
    - Fix flipped frame in avfilter
- Compatible with msvcp 14.40+


# 0.28.0

- Support [rendering in a foreign render pass](https://github.com/wang-bin/mdk-sdk/wiki/Render-API#render-in-a-foreign-render-pass) for all renderers. Previously only foreign opengl context are implemented. The performance should be better than rendering to texture. Now it's able to [render in a Qt RHI window](https://github.com/wang-bin/mdk-examples/tree/master/Qt/rhiwindow)
- Support decoding A53 closed caption in all video decoders. Previously only supported by ffmpeg hwaccels and software decoder. Can be disabled by player property "cc=0".
- Add new [player properties](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#void-setpropertyconst-stdstring-key-const-stdstring-value): "buffer", "audio.decoders", "video.decoders". Convenient to control player in [flutter](https://pub.dev/packages/fvp).
- Support video frames with negative stride, frames are vertically flipped
- BRAW: support 4.0 SDK, compatible with 3.0
- Improve NALU start code and EBP search
- VT decoder:
    - fix hevc mpegts decode error after seek
    - max continuous session restart on error is 1 by default, controlled by property "error=1"
- MFT: fix mf shutdown too early and crash when releasing a sample after stop
- Fix CUDA decoder error after seek. It's a regression in the previous release.
- OpenGL: Fix UBO error, requires glsl150(OpenGL 3.2, ES 3.0)
- Fix alpha channel value of render target when blending subtitle, now output alpha >= background alpha
- Fix multiple frames rendered if prepare() without play
- Fix wrong position() value after prepare() without play
- Fix buffering progress value
- Fix play a new media if previously an individual audio track file/url is used
- Fix endless wait when buffering on apple
- Fix audio channels on apple
- Fix no frame decoded if decoder changed when seeking
- Vulkan: fix wsi extension check
- Metal: fix layer colorspace and disable EDR for SDR
- Fix wrong frame height if copy DX9/11 textures to host memory
- Fix negative duration and start time for live streams, should be 0


# 0.27.0

- Dolby Vision profile 5 support:
    - Works for all renderers: OpenGL, D3D11/12, Metal, Vulkan
    - Support SDR and HDR10 display
    - Works for all decoders. For ffmpeg software decoder and hwaccels, dolby vision metadata are parsed by ffmpeg. For other decoders including ffmpeg external decoders and mdk hardware decoders, metadata is parsed in mdk
- AMediaCodec system dolby vision decoder is disabled by default(previously was enabled). Can turn on via property "dv=1".
- Improve gpu const buffer/uniform update for all renderers
- OpenGL: Support UBO. Enabled for OpenGLES >= 3.0, OpenGL >= 3.1 or extension `GL_ARB_uniform_buffer_object` is supported. Can be disabled via global option "gl.ubo=0" or env var "GL_UBO=0"
- Fix blank display when switching to some videos
- Fix dx swapchain colorspace support check
- Reset some callbacks when destroying player
- Add option "reader.starts_with_key", "0" can decode from non-key. Can be used to reduce latency of network stream
- C++ API:
    - Fix callbacks are not thread safe
    - Fix MediaStatus callback register only once
    - Fix seek, prepare, snapshot callbacks
- Fix video with a single frame not decoded until EOS
- Fix blank display if play another video with only different color primaries
- Fix packet drop
- Fix seek after EOS demuxed
- Use display p3 if hdr10 metadata is invalid
- Read duration from metadata if stream duration is unknown
- Set android application context automatically for ffmpeg 7.0+
- Prefer AudioTrack over OpenSLES
- FFmpeg: Add avformat.video/audio/subtitle_codec_id options


# 0.26.0

- Support WinUI3. `updateNativeSurface()` accepts `SwapChainPanel` as surface like [UWP](https://github.com/wang-bin/mdk-examples/blob/d6035e1450039962577ada748a9be37620c6e6c9/WindowsStore/XamlCx/OpenGLESPage.xaml.cpp#L54)
- Enable UWP features for windows desktop
- Support visionOS
- Add metadata change event `MediaEvent{.category = "metadata"}`, new metadata can be read from `Player.mediaInfo().metadata`. Useful to get icy metadata for SHOUTcast.
- D3D11:
    - Support sync via kmt, requires env var `D3D11_ZERO_COPY=0` and `D3D11_KMT=1`
    - Ignore RTV creation error for shader resource, e.g. textures produced by MFT software decoder via `d3d=11`
- Vulkan:
    - Enable pipeline cache
    - Select the 1st physical device provided by vulkan by default, previously try to use a discrete device
- Fix `Player.WaitFor()` may return wrong value
- Fix YCgCo rendering
- Add global option `plugins.dir`
- Android: link to `libmediandk.so` for 64bit targets
- macOS: fix audio data dropped when paused and results in wrong playback speed
- BRAW, R3D:
    - Fix a crash when stopped
    - (R3D) Fix crash if seek a video without audio track if the previous media has a audio track
    - Build with R3DSDK 8.5.1
    - Support macOS appex, see the [QuickLook plugin](https://github.com/wang-bin/SPV). mdk now weak link to r3d and braw to work in sandbox
    - Fix failed to play a normal video after braw/r3d in the same player instance
    - braw sdk now can be loaded from a custom dir from global option `BRAWSDK_DIR`
    - (BRAW) Fix some memory leaks
- FFmpeg:
    - Support FFmpeg 7.0, now supported runtime versions are 4.0~7.0. Default build version is 6.1, you can remove bundled ffmpeg and add 7.0 shared library|ies to try the new version.
    - Can use avio directly via global option `io.avio=1`, default is via a custom avio
- [Swift](https://github.com/wang-bin/swift-mdk): support cocoapods and swit package manager


# 0.25.0

- D3D11:
    - Improve gpu and cpu 0-copy rendering. Some AMD gpus are disabled because the result is wrong. Can be disabled by environment var `D3D11_ZERO_COPY=0`
    - Improve sync if copy, decode, draw device contexts are different
    - Enable shader_resource in D3D11 decoder by default to support gpu 0-copy rendering, lower gpu load.
    - limit highest feature level to 12.1 to fix device create error
    - Support global device via SetGlobalOption("d3d11.device", devPtr) for both decoders and renderers, then gpu 0-copy will be enabled without issues found in cross device 0-copy, but performance may be lower than cross device 0-copy(tested 8k 60fps av1 hdr with RTX3050)
- D3D12: sync between D3D12/MFT:d3d=12 decoder and renderer
- MFT: `shader_resource` option default value is `1` for MFT:d3d=11 to support 0-copy rendering
- VideoFrame can import an existing d3d11 or d3d9 resources
- Support tvOS
- VT decoder: enable av1, not tested
- CUDA decoder: skip av1C header to fix parse error
- OpenGL: Support GL_EXT_YUV_target, used by android hardware decoder rendering, can be enabled via env var `GL_YUV_SAMPLER=1`
- Fix dead lock if output too many frames in 1 decode
- Fix video size event not triggered for custom readers, e.g. braw and r3d
- Improve overlay rendering
- Wayland: support xdg-shell
- Set subtitle fonts dir and default font file via global option "subtitle.fonts.dir" and "subtitle.fonts.file". Useful for android(lacks of many system fonts). Android subtitle font can be an asset, and then `SetGlobalOption("subtitle.fonts.file", "assets://sub_font_path.ttf")`
- Android: add libass.so in sdk, and will be bundled into your app if use FindMDK.cmake. Remove libass.so from sdk if you don't need it
- Linux: libc++18 compatible


## 0.24.0 - 2023-12-31

- OpenGL:
    - GLRenderAPI.getProcAddress now works, can be provided by user. If not provided, will try to use standard GL library names
    - Support hardware decoder rendering in multiple renderers and multiple threads.
- Vulkan:
    - Support hdr metadata if render context is created in the library via `updateNativeSurface`
    - Support scRGB swapchain
    - Fix invalid framebuffer after resetting render pass(resize error in qmlrhi example).
- Ensure swapchain bufferfs are cleared after stop. Previously only clear once, may result in showing blank image and the last frame repeatly.
- Improve audio/video track switch `Player.setActiveTracks()`, fast and accurate
- Improve (mpegts) program switch `Player.setActiveTracks(MediaType::Unknown, )`, fast and accurate
- If use `updateNativeSurface()`, vo_opaque must be the `surface` parameter.
- VT: Support mpeg4
- AMediaCodec/MediaCodec:
    - property "surface" and "window" to enable tunnel mode, the value is `Surface` jobject and `ANativeWindow*` value string(Previously "surface" value was `ANativeWindow*`).
    - Increase image queue size to reduce acquire errors. max images can be set via decoder property "images=N" or `player.setProperty("video.decoder", "N")`, where N > 1
- Player.record will choose a suitable format if the format guessed from url does not support all codecs. Select correct format for rtmp and rtsp.
- Recorded timestamp is continious and monotonicity by default, required by live streaming. Previous behavior can be enabled by `Player.setProperty("recorder.copyts", "1")`
- Add `MediaEvent{track, "video", "size", {width, height}}` to indicate video track size change, `MediaInfo.video[track].width/height` also change changes
- Improve decoder change event `MediaEvent{track, "decoder.video", decoderName, stream}`, decoderName of hardware decoders is the alias name(e.g. VAAPI), software decoder name is always "FFmpeg". Previously hardware decoderName may be FFmpeg
- Improve packet drop
- iOS: try to load ass.framework and dav1d.framework instead of .dylib
- Subtitle: ignore invalid ass images to fix crash
- Fix crash if audio channels > 8
- Fix thread safe issues for callback setting apis.
- Fix scRGB map in DX and apple
- Fix mpeg4 mosaic after seek
- Fix cmake3.28 xcframework error
- FFmpeg:
    - Add `D3D12` decoder, alias of `FFmpeg:hwcontext=d3d12va`
    - `D3D12` decoder supports 0-copy rendering in a d3d12 renderer
    - Fix wrong audio time base of filter output
    - Fix a potential crash in hw decoder copy mode
- New [.NET binding](https://github.com/axojhf/MDK.SDK.NET/tree/main) and [Avalonia example](https://github.com/wang-bin/mdk-examples/tree/master/Avalonia)


## 0.23.1 - 2023-11-30

- HDR
    - Fix scRGB white level scale
    - Add ColorSpaceExtendedSRGB and ColorSpaceExtendedLinearSRGB. scRGB is used on windows, lumiance is scene referred, while ExtendedLinearSRGB(used on apple) is display referred
- Vulkan:
    - Compress built-in spv via smol-v
    - Add spv for scRGB output
    - Support build shader via shaderc shared library(shaderc_shared.dll, libshaderc_shared.so{,.1}, libshaderc_shared{.1,}.dynamic) if no built-in spv found.
- Add `VideoStreamInfo.image` as audio cover art image
- Apply rotation in recorded video
- Add `MediaEvent{track, "decoder.video", "size", {width, height}}` indicates video frame size changed, value in MediaInfo is also updated
- Add player.setProperty("avcodec.opt_name", "opt_val") to apply AVCodecContext options. For video only codecs, you can also use player.setProperty("video.decoder", "opt_name=opt_val");
- Do not sync to audio if no audio decoded
- AMediaCodec: add property "name" to force a codec name, e.g. `AMediaCodec:name=c2.android.hevc.decoder`.
- MFT: fix d3d=11 driver bug (receive MF_E_TRANSFORM_STREAM_CHANGE endlessly)
- Fix `setBufferRange()` dropping mode incorrectly drops audio packets
- Fix some dead locks


## 0.23.0 - 2023-10-31

- HDR
    - Support scRGB, via `player.set(ColorSpaceSCRGB)`, recommended for windows HDR screen, same experience as system player. You can try it in [QtQuick](https://github.com/wang-bin/mdk-examples/blob/master/Qt/qmlrhi/VideoTextureNodePriv.cpp#L66) app via env var `QSG_RHI_HDR=scrgb`, or in OBS Studio via [the plugin](https://github.com/wang-bin/obs-mdk)
    - Add global option "sdr.white", SDR white level. Default is 203. Can be a different value, e.g. Qt is 100. OBS Studio default is 300 and can be changed by user in settings dialog.
    - Add global option "hdr10.format", Metal only. Metal use rgba16f for HDR10 by default. This can [let QtQuick apps support perfect HDR playback on macOS](https://github.com/wang-bin/mdk-examples/blob/master/Qt/qmlrhi/VideoTextureNodePriv.cpp)
    - Add ColorSpaceSCRGB, ColorSpaceExtendedLinearDisplayP3
    - Fix linear target trc
- Metal: use HLG metadata. use scRGB if requested hdr is not supported.
- Raspberry pi: fix hevc 0-copy OpenGL renderer crash on debian 12. It's a driver bug.
- Decoder options can be set via `player.set("video.decoder", "key1=val1:key2=val2")`
- AMediaCodec:
    - Fix crash if image=1 on api level < 26
    - Do not acquire an image if releaseOutputBuffer error, fix long wait after seek/stop
- Add SeekFlag::SeekFlag for KeyFrame seeking. This can fix EPERM error for some videos.
- `Player.position()` is the last seek request target position when seeking. Previously if seeking is frequent may go back to a previous seek result position then the final position.
- Improve seeking, fix seek request not processed, fix seek callback may be called multiple times
- Fix onFrame() callback sometimes can't get an EOS frame when playback finished or stopped by some reason.
- Fix gpu VideoFrame.to() not in host memory if target format, size is the same as input
- Fix `Player.prepare()` from a position > 0 wrong result if the first decoder fails.
- Fix `waitFor()` dead lock
- Fix PGS subtitle frame duration
- VAAPI: fix undefined symbol on old systems, e.g. ubuntu 16.04
- FFmpeg:
    - Fix audio timestamp if a packet has no pts
- BRAW:
    - Fix crash when destroying player if cuda 0-copy is used
    - Fix OpenCL pipeline, by AdrianEddy


## 0.22.1 - 2023-09-30

- `VideoFrame.timestamp()` is alway readable. `TimestampEOS` indicates no more frames
- Add global option `demuxer.max_errors` to continue on error if error count is less than this value
- MFT:
    - Ignore h264 level by default
    - Fix adapter index if `vendor` property is set, e.g. `MFT:d3d=9:vendor=nv`
- Add `mem` scheme to play from memory, url format is `mem://addr+size`
- VDPAU:
    - Add `interop` property, can be `video`, `output` and `pixmap`. Detail: https://github.com/wang-bin/mdk-sdk/wiki/Decoders#vdpau
    - Use x11 display provided by user except `pixmap` interop
- VAAPI: [document is updated](https://github.com/wang-bin/mdk-sdk/wiki/Decoders#vaapi)
    - Support GLX/EGL texture from dri3 pixmap from drm prime, via option `interop=dri3`, or fallback from `interop=x11` failure. For some drivers(intel iHD driver) it's the only 0-copy solution in GLX context because libva-x11 is broken(vaPutSurface error). `VAEntrypointVideoProc` is requred. Recommend to install `intel-media-va-driver-non-free`, because i965 and free iHD driver may lack of `VAEntrypointVideoProc`.
    - Support `GL_TEXTURE_EXTERNAL_OES` for `dri3` and `x11` interop, via option `external=1`
- DXGI:
    - Fix crash in vm, or no gpu driver
    - Always try rgba8 if fail to create a rgb10a2 swapchain, fix d3d11 feature level 9.3 create render context error
- Try the next decoder if a decoder does not produce any frame. MFT jpeg decoder may produce nothing but no error.
- Fix decode error if previous decoder in decoder list failed
- Fix open a decoder multiple times before trying the next decoder
- Fix pause at eof then stop dead lock if `keep_open` is set(music with cover art).
- Fix incorrect seek request count
- CUDA: fix crash for some unsupported streams, e.g. av1 12bit
- FFmpeg: fix crash if a codec is not enabled
- Add `mdk.pri` for qt qmake projects. All you need is including this file
- Enable full lto to reduce binary size. Thin lto was used in previous versions.


## 0.22.0 - 2023-08-31

- Add `Player.onMediaStatus(MediaStatus oldValue, MediaStatus newValue)` to simplify user code. `Player.onMediaStatusChanged` is deprecated.
- Add player property `avformat.xxx`, `avio.xxx` as as ffmpeg demuxer/io options
- C api module is opensource: https://github.com/wang-bin/libmdk-capi
- If `keep_open` property is set, state changes to `State::Paused` when reach EOS. Also reduce cpu load
- Android:
    - Fix x86 relocation
    - Fix planar formats in OpenSL
- MFT:
    - Support DV video codec
    - Continue if no attributes
- OpenGL: Fix crash if failed to create a context, found in flutter android example
- VAAPI: Flush before seek, fix invalid surface id and crash
- VDPAU:
    - Interop with output surface by default if not nvidia to workaround hevc crash on amd gpus.
    - Prefer interop2 extension
- BRAW:
    - Support build with sdk version 2 and 3
    - Fix 0-copu glitch
    - Dead lock before unloaded
- FFmpeg:
    - hw decoders do not fallback to sw decoder by default, so can correctly switch to the next decoders set in `setDecoders()`. property `sw_fallback=1` to use old behavior
    - Use single thread for hwdec when possible
    - Stop decoding ASAP if hwdec, fix multi-thread hwdec crash on unsupported GPUs, e.g. MX940
- Fix 'file://' on windows
- Fix frames drop in decoders
- Fix loop does not work if audio duration is much smaller than video
- Fix seek may fail if audio duration is much smaller than video
- Fix seek callbacks not called
- Fix `prepare()` fails if previous playback is not finished
- Fix prepare callback is not called if demuxer open error
- Fix seek error for a music with cover art
- Fix crash if unsupported track type is read


## 0.21.1 - 2023-06-30

- Fix loop fails in some ranges
- Raspberry pi: enable eglimage reuse by default to improve 0-copy rendering performance
- API: allow construct Player object from existing ptr
- Android: support assets, via url scheme 'assets', for example `player.setMedia("assets://flutter_assets/assets/test.mp4")`
- Improve av sync
- Braw:
    - upgrade to version 3.1
    - Support iOS
    - Enable 0-copy for cuda
- FFmpeg:
    - Add vulkan decoder `FFmpeg:hwcontext=vulkan:copy=1`, or select another device index `FFmpeg:hwcontext=vulkan:copy=1:hwdevice=1`
    - Fix hwaccel_flags is not correctly applied

* New project: [fvp](https://pub.dev/packages/fvp) is a plugin for flutter [video_player](https://pub.dev/packages/video_player) to support all platforms via libmdk. Add `fvp` as a dependency, and add 2 lines of code, then you can benefit from the power of libmdk. You can try prebuilt example from [artifacts of github actions](https://github.com/wang-bin/fvp/actions)


## 0.21.0 - 2023-05-31

- New D3D12 renderer via `D3D12RenderAPI`. Support all decoders. Performance is similar to D3D11. Optimal texture upload for iGPU, env var "GPU_OPTIMAL_UPLOAD=0" can disale optimal upload to compare performance. You can try [Qt6 QML example](https://github.com/wang-bin/mdk-examples/blob/master/Qt/qmlrhi/VideoTextureNodePub.cpp#L143) or `./glfwplay -d3d12 video_file`.
- D3D11:
    - Texture upload optimize for iGPU on win10. env var "GPU_OPTIMAL_UPLOAD", significantly reduce vram usage, about 50~70%, and even more for compressed textures. Software decoders and built-in hap decoder will benifit from it.
    - Cache shader binaries
    - Fix crash on win7 if default swapchain format is not supported
- DRM Prime:
    - Auto detect external texture requirements via modifiers
    - Fix fd leak in 0.20.0
    - Support reusing EGLImage to improve performance via global option `SetGlobalOption("eglimage.reuse", 1)`, or decoder option `reuse=1`. Known to work for raspberry pi.
- Vulkan:
    - Fix `snapshot()` error, a regression in previous release
    - Fix a crash for Hap videos
- Metal:
    - Fix BC3CoCgSY
    - Support BC formats for iOS 16.4+
- OpenGL: Fix deleting queries without a context, fix potential leaks
- MFT:
    - Supports `d3d=12` option to enable d3d12 decoding. Currently 0-copy renderer is only D3D12, requires `copy=1` option to be used in other renderers.
    - `d3d=11` is default
    - Fallback to lower d3d version or software decoder if open error. So now using `MFT` without option as decoder name is enough.
    - Fix decode error on win7
- VAAPI:
    - [Support windows](https://devblogs.microsoft.com/directx/video-acceleration-api-va-api-now-available-on-windows), backend is d3d12 decoder. Currently only supported by D3D12 renderer 0-copy rendering, or use `copy=1` option for other renderers. Requires dlls from https://www.nuget.org/packages/Microsoft.Direct3D.VideoAccelerationCompatibilityPack can be found by `LoadLibrary()`
    - Fix render error because of drm fd leak
- Raspberry Pi 3/4:
    - Perfectly support h264, hevc hardware decoder and 0-copy rendering in Raspberry Pi OS via `Player.setDecoders(MediaType::Video, {"V4L2M2M","FFmpeg:hwcontext=drm"})`. System ffmpeg is required, MUST delete libffmpeg.so.* in mdk sdk package. May also work with https://github.com/jc-kynesim/rpi-ffmpeg . EGL + OpenGL ES2/3 is recommended by hevc. You can test with `./glfwplay -c:v V4L2M2M,FFmpeg:hwcontext=drm -gl test.mp4`
- Android:
    - AMediaCodec video decoder enable `image=1` option by default, lower latency
    - Fix acquiring AImage when it's not ready
    - Fix jni env detach
    - Add `low_latency` option for AMediaCodec video decoder, default is 0. requires api level 30+
- Fix alpha value for opaque formats in all renderers
- Enable `SeekFlag::InCache` for `Default` flag
- Support programs, add `MediaInfo.program`. `setActiveTracks(MediaType::Unknown, {N})` will select Nth program and it's audio/video tracks will be active. Useful for mpegts programs
- Add `SubtitleStreamInfo.metadata`, subtitle(and other streams) language is `metadata["language"]`
- New pixel formats supported by dx, drm
- Fix a/v sync if audio duration is a lot less than video
- Fix BRAW seek
- FFmpeg:
    - Improve abi compatibility, better support ffmpeg 4.x and 5.x


0.20.0 - 2023-02-28

- Support R3D raw videos via R3D SDK. Document: https://github.com/wang-bin/mdk-sdk/wiki/Decoders#r3d
- Support decoding closed caption for ffmpeg based decoders(FFmpeg, VideoToolbox, D3D11 etc.) and rendering. Add "cc" event when closed caption is detect
- Add drm prime 0-copy rendering, support multi-layers, multi-planes object, support 2d and external texture. Will be used by ffmpeg rpi v4l2 decoder and rkmpp decoder. It should work but not tested.
- Support QSV decoder via oneVPL
- Add video decoder change event https://github.com/wang-bin/mdk-sdk/wiki/Types#class-mediaevent
- FFmpeg: Support 6.0 abi. now the same binary is compatible with ffmpeg 4.4~6.0 runtime
- Improve log
- Reduce shader update for Vulkan and D3D11 renderer
- Fix CUDA and NVDEC not fully enabled on linux
- Fix incorrect `Player.position` if in paused state for videos with no audio track
- Fix incorrect pixel aspect ratio for some videos, prefer the value from decoder(e.g. MFT)
- Fix audio clock not paused if prepare() without play(Apple only).
- BRAW: fix audio not paused if without play
- iOS: fix rejected by app store
- OpenGL: Fix bayer formats not rendered
- VAAPI:
    - Fix derive image
    - Add property "x11", "drm"(or "device") to set x11 display and drm device path(global option "X11Display", "DRMDevice"). "display" option to use "x11" or "drm" display.
    - Improve surface sync
    - Support exporting to an drm prime object with a composed layer with multiple planes. decoder option "composed=1"
    - Add decoder "VADRM" to test exporting drm prime from vaapi
- VT: Use semi-planar formats for macOS11+ & iOS14+ to fix unsupported default output formats
- Add VC-LTL build for windows desktop
- Support build plugins(braw, r3d) with sdk + abi headers. Add global options "plugins_dir"



0.19.0 - 2022-12-28

- New: support subtitle rendering. Can be embedded or external text/bitmap subtitle tracks. The first embedded subtitle track is enabled by default. Use `setActiveTrack(MediaType::Subtitle, ...)` to switch embedded subtitle track. External subtitle must be explicitly enabled by user via `setMedia(file, MediaType::Subtitle)`, and must call it at some point after main video `setMedia(mainVideoFile)`. Text subtitle is rendered by libass, only windows desktop and macOS prebuilt libass is provided for now. Linux users can install system libass. Text subtitles must be UTF-8 encoded.
- API:
    - add Player.enqueue(VideoFrame) to draw a frame provided by user
- Change frame timestamp precision from millisecond to microsecond
- Fix wrong display aspect ratio
- Improve redraw for D3D11, Metal and Vulkan
- Reduce frame queue in renderer to fix some decoders(MFT) may fail to output frames
- VT:
    - add property "fourcc", "CVPixelFormat" to force an output format
    - more pixel formats
    - fix color range error
- QSV: support d3d11. add `d3d` option, can be 11(default for ffmpeg5.0+) or 9.
- FFmpeg:
    - log level for ffmpeg class, for example SetGlobalOption("ffmpeg.log", "trace=tcp")
    - Check opt availability before set, no more warnings
    - Fix unknown media type crash


0.18.0 - 2022-11-16

- API:
    - Add Player.set(ColorSpace), supports auto HDR display, SDR to HDR or HDR to SDR tone mapping. [More details](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#player-setcolorspace-value-void-vo_opaque--nullptr)
- Support HDR display for D3D11 and Metal. If a swapchain and metal layer is provided in RenderAPI, and Player.setColorSpace(ColorSpaceUnknown), then hdr display will be automatically enabled when possible.
- AMediaCodec:
    - "surface" property can be ANativeWindow address to decode video into user profided surface from SurfaceView, SurfaceTexture etc.
    - Add "image" property to support AHardwareBuffer as output, default is "0", can be enabled by "1". Requires android 8.0+.
- VT:
    - Fix frames sorting for some videos
    - Ignore reference missing error
- Fix wrong playback rate on apple if replay after playback end
- Fix audio timestamp is not monotonic for some streams and result in playback stuttering
- Fix decoding image is slow
- Fix global options are not correctly applied
- Fix HLG is not correctly set on MFT decoded frames
- Vulkan: fix crash on macOS with new drivers
- BRAW: fix file path encoding
- Fix some crashes
- Increase frame queue size in renderer, drop frames less
- Improve logging
- Global options changes:
    - "log" == "logLevel", "ffmpeg.log" == "ffmpeg.logLevel"
    - Add "profiler.gpu", shows gpu time for a frame in log


0.17.0 - 2022-09-30

- MFT:
    - Support vc1, wmv, opus, amr, wma, dolby audio
    - Fix mpeg4, enable mpeg2/4
    - Flac partially works, but disabled by property "blacklist=flac"
- Add D3D11RenderAPI.vendor to choose gpu vendor, case insensitive. For example "nv" will select nvidia gpu
- MediaInfo.bit_rate is updated in real time
- Improve audio track switch when playing
- MediaStatus is Invalid if no track found
- D3D11: always flush after renderVideo
- Fix position error if audio has a cover art
- Fix ALSA dead lock if stopping player in paused state
- Pause clock when buffering
- Fix network stream frame update after buffering (apple)
- FFmpeg:
    - Fix D3D11 vc1 decoding
    - Fix audio decode error when seeking ts
    - Fix probing dts audio in ts
    - Fix filter is initialized twice
    - Fix frame pts abi
    - Improve encoder
- New [Flutter desktop example](https://pub.dev/packages/fvp)


0.16.0 - 2022-08-28

- Blackmagic RAW playback support, decoder name is [`BRAW`](https://github.com/wang-bin/mdk-sdk/wiki/Decoders#braw). [Plugin is opensource](https://github.com/wang-bin/mdk-braw)
- Seek callback will always report the correct result position
- Improve seek
- Fix D3D/MFT decoder + WGL on windows may displays green image
- Supports DNG
- More pixel formats, bayer, float rgb etc.
- Fix audio crash on win7
- Fix snapshot crash if render with transform, fix incorrect transform if point map is set
- VideoFrame.to() will copy to host memory first if necessary
- Fix decoded video timestamp maybe not monotonic


0.15.0 - 2022-06-30

- Add new decoder "hap" to decode Hap1, Hap5, HapY and HapM videos into compressed gpu textures(BC1~4). Only desktop platforms are enabled. It's preferred over "FFmpeg" if Player.setDecoders() is not called by user. See https://github.com/wang-bin/mdk-sdk/wiki/Decoders#hap
- Support gpu accelerated Hap rendering via decoder name "hap".
- Support backward seek by frame. `pos` in `seek(pos, SeekFlag::FromNow|SeekFlag::Frame)` can be negative, -1 means go back 1 frame.
- Add SeekFlag::InCache to support seeking in cached data to improve online video seeking. Target position must be in range `(position(), position() + Player.buffered()]`.
- VT Supports mpeg2video
- `VideoFrame.save()` can save original data. Also select closest format if save as an image.
- Improve rendering RGB with X/0(unused alpha channel) formats
- Fix position() is not correctly when seeking by frame.
- Fix playback may stop unexpected, and seeking is slow if seek near EOF
- Fix wrong playback speed if resume from paused state on apple platforms
- Fix empty png snapshot
- Fix snapshot error on OpenGL ES2
- Fix A-B loop may block if too many players
- Fix wrong `Player.position()` and audio timestamp if `playbackRate()` != 1
- Fix `prepare()` callback not called or called many times
- Fix shader compiling affected by locale and may crash, e.g. LC_ALL == de_CH
- FFmpeg:
    - Improve avdevice playback
    - Supports ffmpeg 5.1+


0.14.2 - 2022-04-30

- CUDA decoder:
    - support av1 8 and 10 bit
    - support gray format (mjpeg)
    - fix context error, which results in jpeg decode error
- VT decoder:
    - support deinterlace and enabled by default
    - add "threads" property for software decoding
    - support 16bit yuv with alpha, e.g. ProRes with alpha
    - disable h264 422 10bit for macOS < 11.0. decoded image is corrupt(macOS bug?)
    - fix color info from decoder
- Support dav1d 1.0
- Improve playing live recording ts file near EOF
- Fix record before running state
- Fix recorded video may be malformed when using hardware decoders
- Fix loop at end does not work if "continue_at_end" property is set


0.14.1 - 2022-03-18

- Fix android undefined __emutls_get_address
- Improve accurate seek and seek callback
- D3D11: fix rendering MFT output w/o hw decoding
- D3D11: Wait for fence in gpu
- Support rendering float 16/32 textures
- Fix packed yuv may not be correctly rendered
- Fix mediaInfo() crash
- Support exr image
- VT: support more codecs, including ProRes Raw


0.14.0 - 2022-02-01

- API:
    - Add `Player.setPointMap()`
- Fix Player::foreignGLContextDestroyed() does nothing. Useful to realease gl resources if player is destroyed before context
- Release GL resources ASAP.
- Fix realtime streams frame drop
- Fix rtp decode error
- Fix a crash if recreate opengl context frequently
- Fix macCatalyst build, fix macOS < 11
- Fix ffmpeg av1 can not fallback to dav1d
- Fix metal snapshot and resize renders a green frame
- Fix seeking may output a frame with wrong timestamp


0.13.0 - 2021-12-26

- API:
    - Add Player.setFrameRate(). Default is 25fps if no timestamp in stream.
- MFT:
    - Fix crash on some new drivers
    - Add "activate" property to select mft plugin
    - Add "threads" property for software decoding
- VT:
    - Support more 420, 422 16 bit semi-planar formats, use the closest format
    - Support HEVC with alpha
    - Support HEVC gray formats
- AMediaCodec:
    - Support decoding dolby vision profile 5
- Enable YUV with alpha for all renderers
- Support semi-planar yuv with alpha: NV12A, P416A, 16bit gray format L016
- GL, D3D11, Metal timestamp query
- Fix fail to render hw frame mapped to host for all renderers
- Fix wrong OpenGL blend state
- Fix D3D11 renderer crash on device change
- Use vulkan loader set by env var `QT_VULKAN_LIB` or `VULKAN_LIB`
- Fix CUDA decoder crash
- Fix subtitle endless decode loop at EOF
- Compat with latest FFmpeg 5.0 abi


0.12.0 - 2021-06-26

- API:
    - Add Player.setVolume(float value, int channel) to control channel volume
    - Deprecate setState(State), use set(State)
    - Add GetGlobalOption()
- Fix uyvy422, yuvy422 rendering
- Fix MediaInfo.start_time if < 0
- Fix crash in decoder name is not supported
- Fix a track may endless wait for loop end
- Fix muti-tracks stream can not loop
- Fix slow down near EOF in loop mode at high playback rate
- Fix VAAPI not work in wayland
- VT decoder:
    - Fix decoder stops when bad data error occurs
    - Fix frames are out of order from the 2nd loop
- D3D11 prefers fence for synchronization.
- FFmpeg: support 4.x and 5.x abi, prefer 5.x


0.11.1 - 2021-05-16

- Deprecate Player.setState(State), use Player.set(State)
- Add VideoFrame.save() to encode and save as a file
- Buffer range for realtime streams(rtsp, rtp etc.) is unlimited by default
- Unify pixel format channel map algorithm. Fix incorrect color for some formats(e.g. nv21)
- Ignore incorrect hdr metadata
- Allow renderVideo() in RenderCallback
- VT decoder:
  - Support jpeg, more prores profiles
  - Support h264, hevc GBRP 8bit input pixel format
- MFT:
  - Fix h264 profile check
  - Add property "blacklist", default is "mpeg4", mpeg4 is not well supported so disabled for now
- FFmpeg:
  - continue to decode by default if error ocurrs. can stop decoding by setting property "error=0"
  - Use 4.4 instead of master because of abi break
- Auto reset log handler to fix potential crash when exiting
- Fix seek on pause may never be executed forever without resume playback
- Fix endless wait if seek near EOF in loop mode
- Fix license check, appid is utf8. License generator and validator is opensource now as [appke](https://github.com/wang-bin/appkey)
- Fix crash if snapshot failed


0.11.0 - 2021-03-31

- API changes:
    - Add [setActiveTracks()](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#void-setactivetracksmediatype-type-const-stdsetint-tracks)
    - Deprecate `javaVM(JavaVM*)`, use `SetGlobalOption("jvm", void*)` instead. [See Wiki](https://github.com/wang-bin/mdk-sdk/wiki/Global-Options)
    - Deprecate `setLogLevel(LogLevel)`, use `SetGlobalOption("logLevel", name or LogLevel or int value)` instead. See Wiki](https://github.com/wang-bin/mdk-sdk/wiki/Global-Options)
    - Deprecate `Player.setVideoDecoders(...)` and `Player.setAudioDecoders(...)`, use `Player.setDecoders(MediaType, ...)` instead
    - Add VideoFrame.isValid()
- Add ["dav1d"](https://github.com/wang-bin/mdk-dav1d) decoder. Default load libdav1d.5.dylib, libdav1d.so(android), libdav1d.so.5(linux), libdav1d.dll(windows), or set library name via environment var "DAV1D_LIB"
- Support frame step forward via `seek(1, SeekFlag::FromNow|SeekFlag::Frame)`, also support N frame forward
- `seek()` supports seeking to the last frame or the last key frame(has `SeekFlag::KeyFrame`) if target position > duration
- Improve video decoder switch
- setLogHandler(nullptr) once to log to std::clog, set again to disable log completely
- Fix potential endless wait if stop playback in loop mode
- Fix the first frame after seek is not the latest frame
- Fix music cover image not rendered if prepare from pos > 0
- Fix wrong position() and prepared callback invoked multiple times if play with an audio track file
- Fix the first frame rendered after seek is not the lastest frame
- FFmpeg:
    - Support avdevice via "avdevice://format:filename"
    - Support avformat options via url query, starts with "mdkopt=avformat", e.g. "some_url?mdkopt=avformat&fflags=nobuffer"


0.10.4 - 2021-02-17

- Support macCatalyst
- Support vulkan on apple silicon
- VT decoder:
    - Support VP9 on macOS 11+. Profile 0 and 2 are confirmed
    - Support more(all) semi-planar formats, output a format with the same chroma subsample size as original format, e.g. 'p410' for hevc yuv444p10le.
    - Fix high depth channel formats output error on apple silicon. It's r10g10a10a2 for 10bit Y plane, but not support yet in renderer, so use p010('x420')
    - Add "hardware" property to enable/disable hardware acceleration
    - Add "width" and "height" property
    - Support HDR in mkv
    - Reduce compressed packet copy
- VAAPI, VDPAU: fix not work since 0.10.2
- MFT video decoder: fix h264 constrained baseline profile check
- CUDA decoder: fix chroma format
- FFmpeg:
    - Fix a crash if avio open error
    - Fix "drop" option does not work correctly
- Improve decoder switch in paused state
- Fix can't switch to a new decoder via setVideoDecoders() since 0.10.0
- Fix a blank frame in gapless playback
- Fix 2 crashes in player dtor, 1 race in setNextMedia(), 1 race/crash if faile to open a media
- Examples:
    - Enable glfw for apple silicon


0.10.3 - 2020-12-31

- Player.setMedia() will stop previous media
- Default buffer range changes to 1000~2000ms
- Deprecate `foreignGLContextDestroyed()`, does nothing now. Use `setVideoSurfaceSize(-1, -1)` instead
- Support key-frame only decoding via env "KEY_FRAMES_ONLY=1" (per player option will be better)
- Support play/seek dynamic duration streams, e.g. recording mpeg ts
- Support 'x444'/p410 pixel format
- OpenGL:
    - smart resources release, no leak even if no context destroyed
    - fix external image in essl3 may crash on android
- VT decoder:
    - force nv12 for mpeg?video
    - support hevc yuv444p10le decoded format 'x444'
- Change macOS framework struct to support codesign better
- AMediaCodec decoder: use baseline as fallback of CBP(constrainted baseline) to fix decoder open error
- Fix crash when destroying player if use native surface
- Fix unable to seek if EOS is decoded
- FindMDK.cmake:
    - support xcframework
    - support android studio
- New swift binding: https://github.com/wang-bin/swiftMDK
- New android java wrapper and example: https://github.com/wang-bin/mdk-android


0.10.2 - 2020-11-18

- Support apple silicon(not tested on real device)
- Support swift language
- Support cocoapods for macOS via `pod 'mdk'`
- Add xcframework, including both macOS and iOS frameworks
- Add av1 support for CUDA decoder
- check pixel format support for mmal to fix yuv444p error
- mmal decoder: force copy if no 0-copy support
- Add ACES HDR tone map, via env `GPU_TONE_MAP=aces`
- Metal, d3d11, vulkan renderer support alpha blending if video has alpha channel
- Metal: fix crash if frame is invalid
- Fix a/v sync regression after seek since v0.10.1


0.10.1 - 2020-10-05

- Vulkan: support Player.snapshot()
- GLRenderAPI.egl/opengl/opengles combinations
- Fix Player.setProperty("audio.avfilter")
- D3D11 supports shared nt handle 0-copy rendering via decoder "D3D11:nthandle=1"
- Simplify ffmpeg runtime loading
- Fix some crashes and endless waits


0.10.0 - 2020-09-01

- API:
    - Add VulkanRenderAPI
- Support Vulkan: win32, macOS, android(buggy). Everything works except hardware decoder 0-copy rendering, only software decoders and hardware decoder with ":copy=1" are supported.
- Correct HDR trc if obviously wrong from decoder(mediacodec vp9)
- AMediaCodec:
    - Improve async mode
    - Fix blocks on some devices
- No need to call setLogHandler(nullptr) manually
- Remove redundant gpu color primaries convertion
- Fix D3D11 hevc decoder wrong result because of ignoring profile/level
- Fix D3D11 decoder + D3D11 0-copy rendering wrong result on RTX2060
- Partialy upport mac catalyst build


0.9.2 - 2020-07-29

- API:
    - Add version()
    - Add `Player.set(VideoEffect effect, const float& values, void* vo_opaque)` to set brightness, constrast, hue, saturation
- Metal: Fix viewport resize if create from user provided view
- D3D11/Metal: Fix stop playback does not clear background
- Fix XAudio2 crash on win7, fix leak
- HDR:
    - support HLG transfer function
    - use primaries from decoder(maybe wrong values) iff env "USE_METADATA_PRIMARIES" is 1
    - tone mapping improves
- Add AV1 for android "AMediaCodec" decoder
- Fix another A-B range loop endless waiting
- Vulkan WIP: apple, swapchain, debug, queue, apis, clear background render pass etc.


0.9.1 - 2020-06-30

- API:
    - D3D11RenderAPI.rtv can be a texture to reduce platform dependent user code, context is optional if rtv is set
    - Add GLRenderAPI.fbo, so no need to bind & restore fbo in user code
    - Add MDK_strdup(). Fix potential crashes if msvc build configuration(Debug) != SDK(Release)
- HDR:
    - BT.2390 is the default tone map curve. Controlled by env GPU_TONE_MAP=2390/hable
    - All decoder and renderer combinations has almost the same result
- MFT:
    - Read HDR metadata
    - Support AV1 decoder, need to install av1 extension from store: https://www.microsoft.com/en-us/p/av1-video-extension/9mvzqvxjbq9v
- Clear background on stop can be disabled by SetGlobalOption("videoout.clear_on_stop", 0)
- Default log level is Info. Must manually set to Debug to see more. playback progress log only appears in LogLevel::All
- Seek: ensure the last request will be executed. Useful for timeline preview
- Fix D3D11 backbuffer resize error
- Fix A-B range loop endless waiting if stop playback by user
- Fix change decoder error and wait forever near EOF
- Fix D3D11/Metal renderer crash if change from GPU decoder to CPU decoder
- Fix D3D11RenderAPI.feature_level
- Fix mute crash (avfilter)
- Fix crash if a chapter tile is empty
- Fix failed to save snapshot as png
- Fix win64 cmake search dir
- Deploy: requires vcruntime140_1.dll by win64
- WIP: vulkan


0.9.0 - 2020-05-28

- API: Add GLRenderAPI and MetalRenderAPI
- Support Metal on macOS and iOS. Lower CPU and GPU load.
- Windows:
    - Fix com initialization may affect cef
    - D3D11 support decode in 1 gpu and render in another (poor performance).
    - D3D11 upport some 16bit pixel formats if R16 is not supported
    - Add D3D11 debug mode for MFT decoder("MFT:debug=1") and D3D11 renderer
- Android:
    - Fix EGL load
    - Fix decoding EOS frame in sync and async mode
- Apple
    - Add debug symbol
    - (macOS) weak link to standard ffmpeg dylibs so no need to dlopen by user. see https://github.com/wang-bin/mdk-sdk/wiki/FFmpeg-Runtime#macos
    - Support software decoder direct rendering, decode to CVPixelBuffer via decoder "FFmpeg:pool=CVPixelBuffer". Less memory use.
    - VT decoder supports ProRes, decode into P010 frames
- FFmpeg:
    - Print ffmpeg logs in log mdk log handler. Fix multi-lines logs not print completely
    - Support reload via library handle
    - Custom frame pool
    - Add "sw_fallback" property
- Examples:
    - Modified apple official metal example: https://github.com/wang-bin/HelloTriangle/tree/master
    - QtQuick RHI example. supports d3d11, metal and opengl: https://github.com/wang-bin/mdk-examples/tree/master/Qt/qmlrhi


0.8.1 - 2020-04-30

- API:
    - Player.onSync() default interval is 10
    - Add options for creating D3D11RenderAPI
- CUDA: supports decoding yuv444 formats and 0-copy rendering
- Support rendering gray formats
- Fix MFT:d3d=11 texture leak
- Fix Player.setMute()
- Player.setState(State::Stopped) is much faster
- Fix seek error after setPlaybackRate() if sync to audio
- Apple: enable arc


0.8.0 - 2020-03-18

- API:
    - Add Player.mapPoint() to map coordinates between video frame and viewport
    - Aspect ratio change: negative is scale and crop, positive is scale without crop
    - Add Player.onSync() to support sync to user provided clock. Currently only video can sync to it
- D3D11 renderer:
    - Supports 16bit be formats
    - Convert to rgb by cpu if format is not supported
- Linux multi arch cross build. Less platform specific code
- Add V4L2M2M decoder
- Improve EGL
- Fix a crash on macOS when destroying player
- `setBackgroundColor()`: always draw background if color is valid. Fix regression since 0.7.0.
- Fix playback speed is too fast if resume after paused seek. Regression since v0.5.0
- Fix video only stream clock sync if change playback rate
- Fix wrong position when seeking (if media 1st pts > 0)
- GLX is not linked
- Use clang-8 for rpi to fix invalid armv6 so
- Fix undefined symbol for sunxi
- Enable cf guard for windows


0.7.0 - 2020-02-17

- API:
    - add `Player.setProperty()`
    - add `VideoFrame` class
    - add `Player.onFrame()` to get decoded frame, can be used by custom filters
    - support `MediaStatus::Seeking`
    - add snapshot [MediaEvent](https://github.com/wang-bin/mdk-sdk/wiki/Types#class-mediaevent)
    - `seek()` callback parameter is -2 if seek request is ignored
- ABI: no break
- `setBackgroundColor()`: if alpha is 0(default), you have to call `glClearColor`(or d3d11 api) manually.
- Add FindMDK.cmake in sdk lib/cmake dir, support multiple target architectures.
- Fix multiple D3D11 renderer crash
- Fix crash if audio device is not available
- Fix music with cover buffering progress error
- Fix last frames not rendered if prepare() from a position closed to end of stream.
- Player.setVideoSurfaceSize(-1, -1) can remove the renderer
- prepare() starts from 0 if requested start position > stream duration or duration is unknown
- Improve A-B loop if B is closed to or larger than end of file
- Fix block if A-B loop restarts when previous seeking is not finished
- Music with cover art: fix png not rendered. fix block if stop by user.
- Seek:
    - Fix SeekFromNow
    - Fix audio file read error after seek
    - When end of stream decoded and in paused state
    - Fix seek never work if previous seek failed
    - position() never change after a seek error or a frequent seek request
- snapshot: fix msvc crash
- OpenGL:
    - Save and restore blend states
    - Skip loading EGL if context is not created by mdk
- FFmpeg:
    - support avfilter complex filters via Player property ["video.avfilter" and "audio.avfilter"](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#void-setpropertyconst-stdstring-key-const-stdstring-value)
    - Optimize audio filter if in/out parameters are the same
    - Improve video encoder
- VT decoder:
    - Fix the last frame not rendered
    - Support AnnexB streams
- Reduce exported classes
- Fix crashes, memory leaks in stress tests.
- Metal renderer: WIP
- Audio encoder: WIP


0.6.1 - 2020-01-05

- Improve D3D11 renderer, more pixel formats
- Player.snapshot() supports saving to file
- Support QSV decoder via DXVA2, and 0-copy rendering
- Subtitle WIP.
- Encoder WIP.
- Fix endless wait in loop mode
- Environment var name change: GL_MMAL_FORMAT=>MMAL_GL_FORMAT, GL_VAAPI=>VAAPI_GL, GL_VDPAU=>VDPAU_GL


0.6.0 - 2019-12-02

- D3D11 Renderer: now has almost the same features as OpenGL renderer
    - HDR tone mapping support
    - Support UWP. `ICoreWindow` or `ISwapchainPanel` can be used as the surface of `Player.updateNativeSurface()`
    - Zero copy rendering for hardware decoders, including d3d11, dxva2 and cuda based decoders.
    - Add env vars "SWAPCHAIN_BUFFERS", "DXGI_ADAPTER_RENDER" and "GPU_DEBUG" to control swap chain buffers adapter index and debug layer
    - Support feature level 9.1~12.1(default), controlled by env "D3D_FEATURE_LEVEL_RENDER"
    - Save and restore pipeline states before and after rendering
    - Support foreign context provided by user via `Player.setRenderAPI()`, `D3D11RenderAPI.context` and `D3D11RenderAPI.rtv` must be provided
    - Remove restriction of calling `Player.setRenderAPI()` before any other apis have `vo_opaque` parameter. `updateNativeSurface()` still have to be called after `setRenderAPI()`
    - Support more pixel formats, including nv12, p010 etc. Packed formats with 3 channels are not supported by d3d11 without cpu convertion, leaves them as unsupported.
- MFT: decoder device feature level can be set by property "feature_level"
- Reduce cpu load on pause
- Range loop: fix seek to A failure
- macOS:
    - Fix ui apis called on non-ui thread when creating CGL context(crash on macOS 10.15+)
    - Weak link to libffmpeg.4.dylib because macOS 10.15+ disallow dlopen. also can be replaced by user provided ffmpeg libraries(avutil, avcodec etc.) at runtime via `SetGlobalOption("avutil", (void*)handle)`
- FFmpeg:
    - Set ffmpeg module handle via `SetGlobalOption("name", (void*)handle)`, where name is avutil, avcodec, avformat etc.
    - Fix crash if custom ffmpeg libraries are not complete. Required modules are "avutil", "avformat", "avcodec"
    - D3D11 decoder improve
    - Fix VAAPI seek crash cause by wrong ref count


0.5.0 - 2019-11-03

- ABI Changes:
    - PrepareCallback return type change in Player.prepare()
    - Player.snapshot() callback return type change. Return a file path to save as file(not implemented yet)
    - Add SeekFlag for prepare(), setNextMedia() and gaplessSwitch()
- APIs Changes:
    - Add RenderAPI.h: provides necessary informations to use a graphics api other than OpenGL
    - Add Player.setRenderAPI(): select platform graphics api for video rendering. Now OpenGL(default) and D3D11 are supported.
    - Add version macros
- New Features:
    - Experimental D3D11 rendering support. Now can render frames from software decoders. Color is not precise as OpenGL. Only the context created internally from a HWND via updateNativeSurface is tested. Foreign contexts may work, not tested.
- Improve seeking performance, fix unchanged display when seeking continuously. Now it's close to mpv, and should be better than most players like potplayer, vlc, mpc-hc etc.
- Fix seek position if media start time > 0
- Accurate seek is the default for the start position of prepare(), setNextMedia() and gaplessSwitch()
- OpenGL: Skip uploading video frame to gpu when redrawing
- setState(State::Stopped) now clears video renderer viewport and releases video renderer resources
- Fix stopping playback is not executed immediately
- setState(State::Stopped) now releases host and gpu resouces and clear background color. Normal playback end does not, and still keep the last frame displayed
- Fix setState() sometimes does not work
- MFT Decoder:
    - Disable low latency by default only for hevc. Previous release turned off low latency mode for all codecs, then h264 decoding may be too slow
    - Add property "ignore_profile" and "ignore_level"
- Add FFmpeg decoder property "drop" to control decoder frame dropping when seeking
- glfwplay example:
    - new seek options: `-seek_step`, `-seek_any`
    - support d3d11 rendering using `-d3d11 -gfxthread`


0.4.1 - 2019-10-08

- macOS: fix glx weak link
- support ubuntu >= 14.04
- load vaapi dynamically
- improve vaapi host map, control via env var VAIMAGE_DERIVE, VAIMAGE_FORMAT
- fix many playback loop bugs when more tracks are enabled
- fix too many packets buffered when decoding the 1st frame
- MFT: disable low latency to fix frames out of order
- subtitle support WIP.
    - decode embedded subtitle tracks via avcodec
    - decode loop and thread
- FFmpeg
    - versioned dso is preferred
    - reload ffmpeg symbols if dso is changed by SetGlobalOption()
    - log level is controlled by SetGlobalOption("ffmpeg.loglevel", val), val can be "quiet", "panic", "fatal", "error", "warning", "info", "verbose", "debug", "trace"


0.4.0 - 2019-09-04

- API:
    - add Player.setRange(a, b)
    - add Player.setLoop(count), onLoop(callback)
- Reduce pixel format storage
- Fix onEvent() can not add multiple callbacks
- Support windows on arm64
- VA-API: support map to host
- GL: support creating ES context from WGL
- avglue plugin is now merged into main library
- FFmpeg code is no longer embedded into mdk by default. External ffmpeg4.0+ is loaded automatically. Distributing mdk sdk is easier especially on linux


0.3.1 - 2019-08-15

- fix user stop block
- fix some bugs at eof, e.g. unable to seek
- fix setLoop(0) can not disable looping
- support clang-cl 9.0
- c++ api: support g++ 4.9
- vaapi: sync surface after exporting drm handle
- improve ci. now nightly packages are uploaded automatically to https://sourceforge.net/projects/mdk-sdk/files/nightly
- now mdk can be installed via nuget in visual studio. https://www.nuget.org/packages/mdk


0.3.0 - 2019-08-01

- support A-B loop via setLoop()
- API:
    - fix player.mediaInfo() crash
    - add chapters description in MediaInfo
    - add setLoop()
- GL:
    - add hdr tone mapping. can be disabled by env var "GL_TONE_MAP=0"
    - can create wgl context with specified version and profile
    - improve glsl
- raspberry pi:
    - fix legacy driver check. gl and mmal works correctly on all drivers
    - load libwayland-egl.so.1 when needed
    - mmal zero copy rendering supports yuv textures. not perfect. not the default. enabled by "GL_MMAL_FORMAT=yuv420p"
- MFT(windows media foundation):
    - fix dolby decoder output format
    - input/output type index can be specified by property, example: decoder name is "MFT:in_type=0:out_type=0"
- add missing metadata in MediaInfo
- improve EOS handling in demux thread
- remove terminal null in log
- videotoolbox: stop decoding if decoded frame is invalid
- stop annexb conversion if error occurs
- fix video output drop rate is not desired value
- fix crash if cuda is not available when using CUDA decoder
- fix xaudio2 crash
- fix iOS 32bit min version


0.2.3 - 2019-07-01

- muxer: skip unwanted stream packets
- GL:
    - support gbrp formats
    - improve yuv to rgb
    - xyz gamma correction
- generic color space, trc, primaries support. done in renderer, demuxers and decoders(FFmpeg, VT, AMediaCodec, MFT)
- android AudioTrack: do not use deprecated 7.1 channel value, which may not work in new OSes
- FFmpeg:
    - fix sw format after seek
    - check hw pixfmt of decoded frame, fix sw fallback
    - support avcodec options via property, e.g. FFmpeg:thread=2
- fix annexb check for CUDA, MFT, AMediaCodec decoder
- try next decoder set by user if failed to decode a frame
- AMediaCodec decoder:
    - profile, level and capabilities check before using a codec
    - fix nv12 plane line size in copy mode
    - async mode support
    - detect decode error
- VT decoder(VideoToolbox): add property "copy"
- MFT decoder:
    - apply property "copy", "pool" on the fly
    - fix annexb check
- raspberry pi:
    - enable builtin mmal decoder. decoder name is "mmal", while FFmpeg's is "MMAL"


0.2.2 - 2019-06-05

- API changes:
    - add Player.record()   to record while playing
    - add SetGlobalOption(), can be used to set ffmpeg runtime paths via key "avutil_lib", "avcodec_lib" etc.
- ABI break: no
- NEW:
    - add NV24/42
    - GL: support xyz12le/be
    - MFT: support D3D11 for win7
    - support color space, primaries, trc, range, hdr metadata for VideoFrame, MediaInfo, decoders(except android) etc.
    - support HDR10 for windows GLES2/3(ANGLE) via environment var "D3D11_GL=eglpbuf"
    - support muxing
- fix m3u check
- GL: scale high depth color depends on channel shift
- ci: add azure macOS + iOS build
- iOS: fix arm32 c++17 build(aligned allocate), disable private symbol texImageIOSurface
- free for gpl softwares


0.2.1 - 2019-04-28

- support win arm64 via clang, support llvm-rc
- AVGlue:
    - support user specified FFmpeg runtime libraries instead of built-in ones via environment var: AVUTIL_LIB, AVCODEC_LIB, AVFORMAT_LIB, AVFILTER_LIB, SWRESAMPLE_LIB
    - add FFmpeg decoder property "codec": glfwplay -c:v FFmpeg:codec=...
- Fix MFT p010 frame stride
- Fix cuda api

0.2.0 - 2019-04-01

- API:
    - add setBufferRange()
    - add/removeListener()=>onEvent()
    - add MediaInfo
    - add snapshot()
    - add setBackgroundColor()
- C ABI: should be stable
- New:
    - support dropping outdated packets for realtime streams
    - support fast accurate seek
    - auto rotate
    - switch decoder on the fly
    - first frame rendered event
- Fix m3u8 demux
- Fix a/v sync if audio thread exits earlier
- Fix incorrect buffering progress
- Fix undefined ndkmedia symbols at runtime and crash
- rpi: add native mmal video decoder(disabled now)
- rpi: fix eglimage cache
- rpi: start to adding omx
- MFT: check h264 constraints


0.1.0 - 2019-02-25

- ABI and API change. Single C/C++ SDK is compatible with any C++11 compiler and runtime. Library APIs moves into abi namespace.
- Hide more unnecessary symbols
- Simplify udio channel map
- Do not render audio if no audio device. crash fix
- Fix buffered bytes
- Implement CUDA decoder. Should be better than FFmpeg's CUVID.
- Use exported symbol `void* GetCurrentNativeDisplay()` in main to support vaapi/vdpau+x11egl interop


0.0.10 - 2019-01-28

- Individual audio tracks support.
- MFT decoder improve
    - crop visual area
    - decoded frame copy mode option
    - fix crashes
    - d3d11 0-copy rendering jitter fix
    - add audio decoders: aac, mp3 support
    - minimize IMFMediaBuffer copy
    - fix undefined MFCreateTrackedSample runtime error on win7
- P010, P016 rendering in OpenGL
- buffering event
- Apple: disable flat namespace
- unify decoder properties: "copy", "format"
- support win32 x86: api ptr type, float point compare
- MediaStatus changes
- fix android mediacodec arm64 lto link
- fix annexb packet filter(affects mediacodec)
- mediacodec: support yuv420p, support level 28 ndk apis and metadata, print decoder name
- vaapi: support info/error callback
- avcodec: fix lifetime of hwcontext(hwdec crash)
- gl: recreate texture before changing parameters to fix wrong display if hwdec=>swdec

0.0.9 - 2018-12-05

- dynamic load vdpau in GLVA module
- P010 for d3d11 decoded frames
- enable thin-lto for all
- fix crash if no egl dll
- fix iOS link error
- pulseaudio wip
- Audio backend refactor: async push backend
- exit dsound thread via event
- Add missing onOpen, onClose, onFlush in video decoders
- Add VideoToolbox(name is "VT") for macOS/iOS, support async mode. h265 hvcC, h264 avcC stream are supported, nal is not yet.
  Better performance than FFmpeg's videotoolbox.
  propertyes: threads, format, realTime, async
- Decode EOS only once to fix MediaCodec block in the end.
- Add MFT based video decoder for Win32(Vista+) and UWP. Supports h264, hevc, vp8/9 etc. Supports software decoding, dxva/d3d11 gpu acceleration.
- Add threads property for FFmpeg based decoders.
- Android: support posting messages from native code. try to load stl.
- WinRT/UWP: support IStorageFile


0.0.8 - 2018-10-07

- GL:
    - do not fill background color
    - fix wrong color if video changes
    - fix redraw in a new gl context
    - restore viewport, bo, shader program after rendering to support embedding in other frameworks
    - fix global vbo attributes changes
    - multi-thread improve
    - support NSWindow
    - fix resizing on macOS10.14
- player
    - Add volume, mute, playback rate, vide scale(including mirror) api
    - add getVideoFrame() to retreive currently rendered frame
    - surface type parameter for updateNativeWindow()
    - default preload policy change
    - render callback parameter to support multiple outputs
- fix gapless switch
- fix buffered duration
- apple: disable time pitch effect which results in inaccurate callback invoking time after AudioQueueReset
- playback rate is implemented in avfilter
- no sw fallback when opening hw decoder
- print build information
- fix old packet is enqueued after seek
- GLVA:
    - vaapi: fallback to drm interop if drm2 is not implemented
    - d3d11: always render mapped nv12 textures in rg format to fix es2 rendering(11 feature level 9.3)
- win32/winrt: observe surface size change via foreign window handle and less user code
- build: icf, clang-cl on windows, libc++ etc.
- test: add glfw, x11 example


0.0.7 - 2018-07-31

- support sunxi cedarv decoder and 0-copy rendering via UMP
- add mediacodec audio decoder
- unify mediacodec audio & video decoder
- improve mediacodec video decoder
- create decoder with options string
- buffering progress in duration
- drop frame less. control via env "VO_DROP"
- no MTA requirement for xaudio2
- player: support multiple renderers
- API: player.setAudioDecoders(...), tiled pixel format, seek flag
- build: improve linux cross build with lib++, support winrt via clang
- GLVA:
    - use native video buffer template except apple
    - vaapi + drm(prime) support
    - fix mapped texture reuse for multi-renderers rendering(except d3d)


0.0.6 - 2018-06-02

- support clang-cl host build and cross build for windows
- support opensource gcc on macOS
- improve Packet.buffer
- support rendering frame whose vertical stride > height
- fix and improve VideoFrame ctor
- fix seek block because of long time sleep
- add MediaStatus::PreparedMedia, fix mediaStatus() bugs
- frame boost options for FrameReader and player prepared callback
- fix wrong frame displayed in gapless switch via frame boost option
- Android AudioTrack support
- Android MediaCodec video decoder support, via ndk api implemented in ndk or jni (JMI+AND project)
- GLVA:
    - test D3D11 nv12 SR texture support
    - map to host support: d3d9, d3d11, vdpau
    - CUDA stream support and enabled by default
    - fix android context change check
    - fix MMAL pool is used for mesa vc4 environment
- AVGlue:
    - use new api avcodec_get_hw_frames_parameters
    - set texture flags via hwframesctx to enable d3d11va-eglstream 0-copy
    - improve Buffer and AVBufferRef, support offset
    - fix mkv packet decode error in ffmpeg4.0+
    - fix mediacodec because of ref leak
    - use CUDA stream shared from glva native buffer pool


0.0.5 - 2018-05-05

- video decoder supports glva via wrapper
- fix mapped host frame stride and format
- qr code overlay and license check module
- OpenSL use system stream type and the sound is louder
- ALSA: fix reopen error
- Support direct sound
- Fix rendering audio with invalid padding data
- GL: grab rendered frame, user shader api
- player: no currentMediaChanged in dtor to ensure accessing player object is safe
- FrameReader: improve AOT frame boost(no api now), improve state update and no more unexpected dead blocks
- Gapless switch improvements(mostly in audio)
- log is default disabled, set null handler behavior change
- build: cmake 3.5+ is required, ubsan, fix header install
- GLVA
    - api change: support multiple textures, no more map callback, frame size parameter
    - NativeVideoBuffer wrapper for c api
    - Fix texture reuse optimization(apple, d3d, mmal)
    - add VA-API interop with X11 Pixmap, for both  EGL and GLX
    - add VDPAU interop with X11 Pixmap, and GLX extension, for both  EGL and GLX
    - D3D9 interop with WGL works now
    - support D3D11 interop with WGL
    - D3D11 interop with EGLStream works now and it becomes the default
    - D3D11 supports texture as egl client buffer(requires ANGLE master)
    - fix potential EGLSurface leak in CVPixelBuffer interop
- AVGlue
    - improve linking static ffmpeg on windows
    - support VA-API, VDPAU
    - less deprecated apis
    - fix AVFrame leak in filter, use smart ptrs for av types
    - fix the case avpacket data is different from buf.data


0.0.4 - 2018-04-07

- requires cmake3, fix x64
- gnu stl is default for rpi
- works with vs2013 again(wgl only)
- frame drop api, no implementation
- support ALSA, it's default for linux
- improve audio renderer: flush, pause, delay, timestamp, unified, write
- remove audio renderer open/close apis. reopen internally when necessary
- improve a/v sync, support no active audio track
- opengl context local storage improvements: per object, custom creator and initializer etc.
- d3d11 interop with angle egl, for desktop and uwp
- fix teared content in d3d11 interop
- apple CVPixelBuffer interop with ANGLE EGL
- disable opengl shader cache sharing
- fix 16bit rendering in ES3
- videorenderer: fix 2d transform matrix(aspect ratio), optimize matrix uploading
- GLVA: refactor, unify and simplify context change handling
- support CUDA
- frame capture api without implementation
- avglue: new ffmpeg hwconfig apis, support nvdec, hw device ctx from us, hw copy decoder, mediacodec hwcontext
