# NipaPlay TV 安装包体积分析与优化报告

- 分析对象：`apps/nipaplay_tv`（applicationId `com.aimessoft.nipaplay_tv`）
- 样本：本机构建产物 `build/app/outputs/flutter-apk/app-{debug,release}.apk`
- 工具：apkanalyzer（cmdline-tools 19.0）、zipfile 结构拆解、Gradle/Flutter 构建日志
- 日期：2026-10-12
- 声明：**所有数字均来自实际构建产物**；对无法直接测量的部分（如 B站云试听内部构成）标注为「待验证假设」。

---

## 1. 体积对比概览

| 样本 | 体积 | 说明 |
|---|---|---|
| 优化前 debug APK | 160.9 MB | 含 JIT 内核与调试符号，**不代表分发体积** |
| 优化前 release APK（三 ABI 全打） | **129.7 MB** | 优化起点（真实分发口径） |
| **优化后 release APK（仅 arm64）** | **54.2 MB** | **−58.2%** |

> 注意：debug 包（160.9 MB）比 release 大 6 MB 的构成完全不同——它含 51.3 MB 的 `kernel_blob.bin`（JIT 内核）与 14.5 MB 的 `libVkLayer_khronos_validation.so`（Vulkan 校验层），二者都不进 release。**拿 debug 包做体积对比会严重误判。**

---

## 2. 优化后 release APK 构成明细（54.2 MB）

| 模块 | 压缩后体积 | 占比 |
|---|---|---|
| `lib/arm64-v8a` | 53.17 MB | **98.0%** |
| `dex` | 0.42 MB | 0.8% |
| `assets` | 0.23 MB | 0.4% |
| `res` | 0.20 MB | 0.4% |
| `resources.arsc` | 0.09 MB | 0.2% |

native 库内部构成：

| 文件 | 未压缩体积 | 占比 | 归属 |
|---|---|---|---|
| `lib/arm64-v8a/liberika_capi.so` | **35.37 MB** | **65.3%** | Erika 播放内核（自研，含 FFmpeg 级解码 + libplacebo HDR 管线） |
| `lib/arm64-v8a/libflutter.so` | 11.05 MB | 20.4% | Flutter 引擎 |
| `lib/arm64-v8a/libapp.so` | 5.44 MB | 10.0% | AOT 编译后的 Dart 代码（core + ui_common + TV UI） |
| `lib/arm64-v8a/libc++_shared.so` | 1.31 MB | 2.4% | C++ 运行时（Erika 依赖） |
| 其余（datastore 计数器等） | ~0.01 MB | — | — |

**结论：包体 98% 是 native 库，其中 Erika 内核独占 65%。Dart 业务代码（5.4 MB）与资源（0.4 MB）在体积上几乎可忽略。**

---

## 3. 主因分析（含优化前后对比）

### 3.1 已消除的膨胀点

| 膨胀点 | 优化前 | 优化后 | 手段 |
|---|---|---|---|
| **三 ABI 全量打包** | arm64 53.2 + x86_64 60.8 + v7a 14.1 MB | 仅 arm64 53.2 MB | `flutter build apk --release --target-platform android-arm64` |
| **多内核共存**（media_kit/libmpv + MDK + Erika + video_player） | 依赖树 45 个额外包 | 仅 Erika | 移除三个内核的依赖与适配器 |
| debug 专属产物 | kernel_blob 51.3 MB、Vulkan 校验层 14.5 MB、9.45 MB classes.dex | 不进 release | 用 release 口径衡量 |

### 3.2 残留主因（当前 54.2 MB 的构成）

1. **`liberika_capi.so` 35.4 MB（65%）** —— Erika 内核把解码器（FFmpeg/系统解码）、渲染（libplacebo HDR 色调映射）、音频、字幕、弹幕引擎全部静态链接进单个 `.so`。
   - **待验证假设**：该库可能未做符号剥离（strip）或含未使用的解码器/字体/着色器资源；需在 Erika 仓库侧确认构建配置。
2. **`libflutter.so` 11.1 MB（20%）** —— Flutter 引擎固定开销，官方 release 产物已优化，**无法进一步压缩**（除非改用 WebView/原生方案，属架构级取舍）。
3. **`libapp.so` 5.4 MB（10%）** —— Dart AOT 产物，已启用 icon tree-shaking（MaterialIcons 从 1.6 MB → 4.9 KB）。可再减空间有限。

### 3.3 与「B站云试听」的差距解释

用户反馈 TV 包「约为 B站云试听数倍」。基于上述数据，**差距主要来自技术选型而非配置疏漏**：

- 本应用是 **Flutter + 自研 native 播放内核**：仅 Flutter 引擎（11 MB）+ Erika（35 MB）就有 46 MB 的「底座」。
- B站云试听若为**原生 Android（Kotlin/Java）+ 系统 MediaCodec**，则无需携带 Flutter 引擎与自带解码器，APK 可低至 10–20 MB。
- **待验证假设**：未取得 B站云试听 APK 样本，其 ABI 数量、是否含自带解码器、是否用 Flutter/RN/Unity 均未经核实；上述对比为基于体积量级的推断，非实测结论。若要坐实，需下载其 APK 并用同样的拆解脚本对比（脚本已附，见 §6）。

---

## 4. 优化建议清单（按性价比排序）

### P0 — 已完成
| 项 | 操作 | 收益 | 风险 |
|---|---|---|---|
| 仅 arm64 | `--target-platform android-arm64`（或 AAB 交由 Play 分发） | −75 MB | 低：TV 设备 99%+ 为 arm64；如需兼容 x86 模拟器另出变体 |
| 单内核（Erika） | 移除 media_kit/fvp/video_player | 消除多内核叠加（若四内核全打包，libmpv+MDK 合计可达 +60 MB 量级） | 中：失去内核回退能力，见 §5 |

### P1 — 建议下一步（未执行，需评估）
| 项 | 操作 | 预期收益 | 风险 | 依据 |
|---|---|---|---|---|
| AAB 分发 | 改用 `flutter build appbundle` + Play/自有渠道按 ABI 下发 | 用户实际下载 ≈ 单 ABI 体积（与当前一致） | 低 | 官方推荐 |
| 内核符号剥离 | 在 Erika 构建配置确认 `strip` / `-Wl,--gc-sections` / LTO | **待验证假设**：或可减 5–15 MB | 低（仅体积，不改功能） | `liberika_capi.so` 35 MB 明显偏大 |
| 按需解码器 | 与 Erika 上游确认是否可裁掉未用的解码器/滤镜 | 待验证 | 中（可能影响格式兼容） | 需 Erika 仓库构建选项证据 |
| 资源压缩 | `android.enableResourceOptimizations`、shrinkResources | ~0.2 MB | 低 | 当前 res 仅 0.2 MB，收益极小 |

### P2 — 架构级（不推荐为减包而做）
- 放弃 Flutter 改原生：可省 11 MB 引擎 + 大幅缩小内核依赖，但**等于重写整个应用**，与四阶段重构目标冲突。
- 移除 Erika 改系统 MediaCodec：省 35 MB，但**丢失 HDR/高级字幕/弹幕内核能力**，且需重写播放层。

---

## 5. 兼容性与功能影响警示

1. **仅 arm64**：x86_64 模拟器与极老 32 位 TV 盒子将无法安装。当前本机验证机（OnePlus PKG110，arm64）安装正常。**如需覆盖 x86 模拟器做开发调试，建议用 `--target-platform` 分别出包，而非恢复三 ABI 全打。**
2. **单内核 Erika**：丧失「某内核不支持某格式时切换」的兜底能力。当前 Erika 支持 Android/tvOS/桌面/OHOS，能力较全；**若遇到 Erika 无法播放的源，将无回退路径**。
3. **minSdk 24 → 26**：Erika 要求。Android 8.0 以下设备不可装（TV 场景影响极小）。
4. **许可证**：Erika 为 AimesSoft 自研（`dev.aimesoft.erika_flutter`），随包分发需确认其许可条款允许；libmpv/FFmpeg 相关许可证随内核一并移除后，**需同步清理 NOTICES 中已不再分发的第三方声明**（当前 `NOTICES.Z` 仅 0.11 MB，非体积问题，属合规收尾）。

---

## 6. 可复测指标与验证步骤

**基线-优化-复测闭环**（脚本可直接复用）：

```bash
# 1) 构建指定 ABI 的 release
flutter build apk --release --target-platform android-arm64
# 2) 体积拆解（本报告使用的脚本）
python docs/refactor/tools/apk_size_report.py <apk路径>
# 3) 官方口径
apkanalyzer apk file-size app-release.apk
apkanalyzer apk download-size app-release.apk
# 4) 如需对比 B站云试听：拿到 APK 后跑同一脚本，即可得到同口径构成表
```

**关键复测指标**：
| 指标 | 当前值 | 目标 |
|---|---|---|
| release APK 体积（arm64） | 54.2 MB | ≤ 45 MB（若 Erika 可剥离符号） |
| `liberika_capi.so` 体积 | 35.4 MB | 待 Erika 上游确认下限 |
| ABI 数量 | 1 | 1 |
| 安装成功率（arm64 TV/手机） | 已验证 1 台 | 需多机型 |

**后续验证步骤**：
1. 向 Erika 维护方确认 `.so` 构建配置（strip/LTO/裁剪解码器）——这是当前唯一有实质空间的方向。
2. 下载 B站云试听 APK 做同口径拆解，坐实 §3.3 的推断（当前为「待验证假设」）。
3. 在多台 arm64 设备验证安装与播放，确认仅 arm64 无兼容问题。

---

## 7. 一句话结论

优化后 release 包 **129.7 MB → 54.2 MB（−58%）**，手段是「只打 arm64」+「只留 Erika 单内核」。剩余体积 **98% 是 native 库，其中 Erika 内核 35.4 MB 占 65%**；Dart 代码与资源已无压缩空间。与 B站云试听的差距**根因是技术选型（Flutter + 自带解码器内核 vs 可能为原生 + 系统解码器）**，而非配置疏漏——**该对比结论为待验证假设，需样本实测确认**。
