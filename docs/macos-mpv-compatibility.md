# macOS mpv Swift 兼容性验证

关联问题：#476、#520、#633、#643。

mpv 使用 `osdep/mac/meson.build` 中的 `custom_target` 调用 Swift 编译器，
并不使用 Meson cross-file 中的 `swift_args` / `swift_link_args`。
HDR 构建必须通过 mpv 自己的 `swift-flags` 参数同时指定架构和系统版本：

- ARM：`-Dswift-flags=-target arm64-apple-macos11.0`
- Intel：`-Dswift-flags=-target x86_64-apple-macos11.0`

CI 中的 `libmpv-darwin-build-macos-swift-target.patch` 给 Nix 配方加入这些参数。
补丁内容进入框架缓存键；修复后不会复用此前的错误缓存。

## 1. 新系统上的编译回归测试

需要完整 Xcode、Python 3、Meson 和 Ninja。在仓库根目录运行：

```sh
python3 -m venv /tmp/nipaplay-mpv-test-tools
/tmp/nipaplay-mpv-test-tools/bin/python -m pip install meson ninja
PATH="/tmp/nipaplay-mpv-test-tools/bin:$PATH" \
  PYTHONDONTWRITEBYTECODE=1 \
  python3 scripts/macos/test_verify_mpv_compatibility.py
```

测试直接使用仓库中 mpv 的 Swift 构建脚本和 builder 的 cross-files，
仅用小型 Swift/C 输入替代播放器源码与媒体依赖。测试验证：

- 即使 cross-file 已设置 Swift target，旧的自定义编译命令仍会遗漏它。
- 旧参数导致交叉编译缺少 mpv Swift 类；新参数在 ARM 和 Intel 中均能链接这些类。
- 最终动态库声明 `minos 11.0` 仍可能引用旧系统没有的 `StaticArrayStorage`。
- Universal 二进制中的非本机架构也接受检查。
- 请求的架构不存在时，检查必须失败。

新系统可以验证编译参数和二进制内容，但不能单凭“新系统启动成功”证明旧系统兼容。
此测试也不代表完整 Nix 媒体依赖或 Flutter 应用已经重建成功。

## 2. 检查真实发布产物

```sh
python3 scripts/macos/verify_mpv_compatibility.py /path/to/NipaPlay.app \
  --require-arch arm64 --require-arch x86_64
```

单架构包只传对应的一个 `--require-arch`。也可以传入 `Mpv` 二进制、
framework / xcframework 目录，或解压后的框架缓存目录。

检查覆盖每个架构的最低系统版本，以及这次回归中的两类未定义符号。
它是针对已知问题的静态检查，不是完整的 macOS API 兼容性扫描。
官方 1.11.5 的 ARM 框架仍强引用 `StaticArrayStorage`，Intel 框架仍缺少四个
mpv Swift 类；这两个真实产物都应检查失败，可作为修复前的对照样本。

发布流程在两处执行此检查：

1. 框架缓存取出或重建后、保存缓存之前。
2. CocoaPods 嵌入框架并生成最终 `.app` 后、签名和打包之前。

## 3. 构建用于验收的完整应用

GitHub Actions 的 **macOS mpv Swift Compatibility** 工作流对相关 PR 自动运行
编译回归测试。手动运行时勾选 `build_packages`，还会复用正常的 macOS 构建流程，
生成 Universal、Apple Silicon、Intel 的应用包，供下载到测试机。
这需要仓库已有的签名 secrets，但不会创建 GitHub Release 或提交应用商店。

该手动入口需要先把工作流加入默认分支，以便 GitHub 注册 `workflow_dispatch`；
本地修改不会自动启动远端 CI。随后可用 `gh workflow run` 选择已推送的测试分支：

```sh
gh workflow run macos-mpv-compatibility.yml \
  --repo AimesSoft/NipaPlay-Reload --ref YOUR_BRANCH \
  -f build_packages=true
```

从该次运行的 `release-macOS-*` artifacts 下载包进行下一步验收。

## 4. macOS 14 虚拟机对照测试

Apple Silicon 主机可通过 Apple Virtualization.framework 运行 ARM macOS 虚拟机。
[Tart 文档](https://tart.run/quick-start/)提供 Sonoma（macOS 14）镜像。
UTM 也是图形界面的选择。镜像和虚拟硬件必须受本机支持；不能仅凭主机系统版本判断。

2026-09-07 在 M5 Pro / macOS 26.6.2 上做的只读预检查结果：

- `VZVirtualMachine.isSupported == true`
- 所选 Sonoma 镜像的 `VZMacHardwareModel.isSupported == true`
- 镜像压缩层约 21 GiB，声明的虚拟磁盘容量为 50 GB；下载缓存会额外占用磁盘。

预检查不等同于已启动虚拟机。建议给缓存与虚拟磁盘预留约 80–100 GB 可用空间。
Tart 的示例创建和运行命令如下；这些命令会安装工具并下载镜像：

```sh
brew install cirruslabs/cli/tart
tart clone ghcr.io/cirruslabs/macos-sonoma-base:latest nipaplay-sonoma
tart set nipaplay-sonoma --cpu 4 --memory 8192
tart run --dir=packages:/absolute/path/to/test-packages:ro nipaplay-sonoma
```

镜像默认账户见 Tart 文档（当前为 `admin` / `admin`）。共享目录出现在客体系统的
`/Volumes/My Shared Files/packages`。把应用复制到虚拟机自己的目录运行。
先用 `sw_vers` 记录实际 macOS 版本，后续不要在两次对照测试之间升级系统。
为了复查可重复性，也应记录使用的镜像 tag/digest；`latest` 会变化。

在同一台虚拟机中依次验证：

1. **旧的 1.11.5 ARM 包**：记录是否出现 `StaticArrayStorage` 的 DYLD 启动错误。
2. **修复后的 ARM 包**：应用能进入主界面，且不再出现该错误。
3. **修复后的 Universal 包**：正常启动，再打开本地视频确认播放内核能初始化。
4. 保存应用版本、系统版本、架构、终端输出及系统崩溃报告。

完整启动日志可通过客体终端直接运行应用主程序并重定向到文件保存。
分别放置旧版和修复版，使用相同的测试文件和干净的测试账户。

Sonoma ARM 虚拟机主要验收 #476 的旧系统运行时问题。
它不模拟 Intel CPU；Intel 包可以在安装了 Rosetta 的 ARM macOS 上执行额外冒烟测试，
但最终仍应请 Intel 真机用户验收 #520 / #633 / #643。
虚拟机图形环境也不能替代外接 HDR 显示器测试，#881 的显示器切换崩溃应单独处理。

Apple 官方说明：
[Running macOS in a virtual machine on Apple silicon](https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon)。
