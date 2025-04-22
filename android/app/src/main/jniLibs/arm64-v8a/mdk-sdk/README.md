## MDK: Multimedia Development Kit
### [Changelog](https://github.com/wang-bin/mdk-sdk/blob/master/Changelog.md)
### [API](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)

### Features
- [Simple and powerful API set](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs)
- [Cross platform: Windows(x86, arm), UWP, Linux, macOS, Android, iOS, tvOS, visionOS, Raspberry Pi](https://github.com/wang-bin/mdk-sdk/wiki/System-Requirements)
- [Hardware accelerated decoders for all platforms](https://github.com/wang-bin/mdk-sdk/wiki/Decoders)
- [0-copy GPU rendering for all platforms and all renderers(Vulkan is WIP.)](https://github.com/wang-bin/mdk-sdk/wiki/Zero-Copy-Renderer)
- [Dynamic OpenGL](https://github.com/wang-bin/mdk-sdk/wiki/OpenGL-Support-Matrix)
- [OpenGL, D3D11, D3D12, Vulkan and Metal rendering w/ or w/o user provided context](https://github.com/wang-bin/mdk-sdk/wiki/Render-API)
- Integrated with any platform native ui apps, gui toolkits or other apps via [OpenGL, D3D11/12, Vulkan and Metal](https://github.com/wang-bin/mdk-sdk/wiki/Render-API) ([WinUI3](https://github.com/Damix48/WinUI3MDK/tree/main), [OBS](https://github.com/wang-bin/obs-mdk), [Flutter](https://pub.dev/packages/fvp), [Qt](https://github.com/wang-bin/mdk-examples/tree/master/Qt), [SDL](https://github.com/wang-bin/mdk-examples/tree/master/SDL), [GLFW](https://github.com/wang-bin/mdk-examples/tree/master/GLFW), [SFML](https://github.com/wang-bin/mdk-examples/tree/master/SFML), [.NET Avalonia](https://github.com/wang-bin/mdk-examples/tree/master/Avalonia) etc.) easily
- [HDR display metadata passthrough, HDR <=> SDR tone mapping](https://github.com/wang-bin/mdk-sdk/wiki/HDR). You can use HDR display in [Qt6(6.6+ for macOS, 6.x for windows)](https://github.com/wang-bin/mdk-examples/tree/master/Qt/qmlrhi), [OBS Studio](https://github.com/wang-bin/obs-mdk), Android SurfaceView and more.
- Dolby Vision rendering, including Profile 5. Support HEVC and AV1.
- HEVC, VP8/9 transparent videos(alpha channel) support for all decoders and renderers
- Professional codecs: GPU accelerated [HAP](https://github.com/wang-bin/mdk-sdk/wiki/Decoders#hap) codec rendering, [Blackmagic RAW](https://github.com/wang-bin/mdk-braw), [R3D](https://github.com/wang-bin/mdk-r3d), [nvJPEG2000](https://github.com/wang-bin/mdk-nvjp2k)
- Subtitle rendering, including ass, plain text, bitmap, closed caption
- [Seamless/Gapless media and bitrate switch for any media](https://github.com/wang-bin/mdk-sdk/wiki/Player-APIs#player-setcolorspace-value-void-vo_opaque--nullptr)
- Optimized Continuous seeking. As fast as mpv, but much lower cpu, memory and gpu load. Suitable for [timeline preview](https://github.com/wang-bin/mdk-sdk/wiki/Typical-Usage#timeline-preview)
- [Smart FFmpeg runtime, dynamic load, binary compatible with 4.0~8.x](https://github.com/wang-bin/mdk-sdk/wiki/FFmpeg-Runtime)


## About SDK for Android
SDK is built with
- ffmpeg: https://sourceforge.net/projects/avbuild/files/android/ffmpeg-master-android-clang-lite-lto.tar.xz/download
- ndk 28
- requires ndk r23 and later because of ndk abi break in r23

SDK can be used by any C or C++11 compiler, e.g. g++, clang

dsym files are debug symbols, not required to deploy your programe.

### [Supported Graphics APIs:](https://github.com/wang-bin/mdk-sdk/wiki/Render-API)
- [OpenGL ES2/3](https://github.com/wang-bin/mdk-sdk/wiki/OpenGL-Support-Matrix)
- Vulkan

### OpenGL Context
- Create by mdk: use SurfaceView's Surface to initialize rendering thread
- Created by user: use GLSurfaceView, TextureView or whatever

### [Supported Decoders:](https://github.com/wang-bin/mdk-sdk/wiki/Decoders)
- FFmpeg
- MediaCodec: FFmpeg mediacodec implementation
- AMediaCodec: builtin mediacodec implementation, using libmediandk or java api

MediaCodec/AMediaCodec decoder will not be destroyed if app go to background, and continues to work when resumed.

### Audio Renderers
- OpenSLES
- AudioTrack (default)

### Data Source
- `content:`
- `android.resource:`
- `assets:`

### Use in CMake Projects
```
	include(mdk-sdk-dir/lib/cmake/FindMDK.cmake)
	target_link_libraries(your_target PRIVATE mdk)
```

### Qt qmake project
```qmake
include($$MDK_SDK_DIR/mdk.pri)
```


### Recommended settings
```cpp
    SetGlobalOption("JavaVM", JvmPtr); // REQUIRED
    player.setDecoders(MediaType::Video, {"AMediaCodec", "FFmpeg", "dav1d"});
```

## Source code:
- [some examples using mdk sdk](https://github.com/wang-bin/mdk-examples)
- [OBS Studio plugin](https://github.com/wang-bin/obs-mdk)
- [QtMultimedia plugin](https://github.com/wang-bin/qtmultimedia-plugins-mdk)
- [MFT decoder module](https://github.com/wang-bin/mdk-mft)
- [dav1d decoder module](https://github.com/wang-bin/mdk-dav1d)
- [Android java wrapper and example](https://github.com/wang-bin/mdk-android)
- [libmediandk and other java classes implemented in C++](https://github.com/wang-bin/AND)
- [JNI Modern Interface](https://github.com/wang-bin/JMI)

Copyright (c) 2016-2025 WangBin(the author of QtAV) <wbsecg1 at gmail.com>
Free for opensource softwares, non-commercial softwares, flutter, QtAV donors and contributors.