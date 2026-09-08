# macOS 启动兼容性验证

macOS 发布流程在 macOS 26 上构建完整安装包，再把同一个 Universal ZIP
交给 macOS 14 Apple Silicon runner 实际运行。ARM64 原生和 x86_64 Rosetta
分别测试：应用必须持续运行 45 秒，并出现属于该进程的主窗口。
这不等同于真实 Intel 硬件测试，也不覆盖播放、HDR 或所有旧系统 API。

## #476 的原因

mpv 的 `osdep/mac/meson.build` 用 `custom_target` 直接调用 `swiftc`，
不会读取 Meson cross-file 的 `swift_args`。仅设置该选项或 C/C++ deployment
target，会留下最低版本标为 macOS 11、却仍然导入
`_$ss20__StaticArrayStorageCN` 的 `Mpv.framework`。macOS 14 在加载时就会终止应用。

`.github/patches/libmpv-darwin-build-swift-deployment-target.patch` 通过 mpv
自己的 `-Dswift-flags`，分别传递 `-target arm64-apple-macos11.0` 和
`-target x86_64-apple-macos11.0`。补丁摘要参与 libmpv 缓存键，确保旧的
不兼容产物不会被复用。

`check-macos-mpv.py` 在缓存保存和后续应用构建之前检查两个架构的最低版本，
并拒绝对该符号的强引用；缓存命中也会执行检查。真正的系统兼容性仍由
`smoke-macos.yml` 的启动测试确认。

## 手动运行

在 Actions 中选择 **macOS Compatibility**，选择需要验证的分支并运行。
默认会从源码构建 Universal 包，不使用发布证书、不发布 Release。
若 `release_tag` 填写 `v1.11.5` 这样的版本号，则直接下载对应的
Apple Silicon 发布包进行诊断。

诊断 artifact 包括 `result.json`、`startup.log`、`unified.log`、可用的
系统崩溃报告、Mpv 的符号及加载命令。源码构建的测试还保存进程采样和
`windows.json`。`result.json` 的 `survived` 和 `window_visible` 均为 true
才代表新构建通过了启动检测。

正式发布仍要求签名和公证凭据，并验证原始包签名；只有显式选择
`unsigned` 的诊断构建才在测试机上执行临时签名。

GitHub 计划于 2026-11-02 停用 macOS 14 托管镜像，届时需要提供仍运行
macOS 14 的 runner。不要直接改成 `macos-latest`，否则将失去旧系统兼容性
验证。参见 [GitHub runner 镜像退役公告](https://github.com/actions/runner-images/issues/13518)。
