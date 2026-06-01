# cpp_native — NipaPlay C++-Dart FFI 框架

## 概述

`cpp_native/` 是 NipaPlay-Reload 中新增的 C++ → Dart FFI 链路（Link C），直接通过 `dart:ffi` 调用 C++20 原生模块，不经过 Rust 中间层。

## 架构

```
Dart (dart:ffi) → C ABI Thunk Layer (extern "C") → C++20 Implementation Modules
```

- **Thunk 层**：每个 `extern "C"` 函数内部做异常安全封装（catch-all），确保 C++ 异常不会跨越 FFI 边界
- **不透明句柄**：`NpHandle (void*)` 在 Dart 侧映射为 `Pointer<Void>`，32/64-bit 自动适配
- **统一错误处理**：`NpResult` 结构体 + Dart 侧 `NativeResult<T>` Result 模式

## 目录结构

```
cpp_native/
├── CMakeLists.txt                # 根 CMake（被各平台构建系统引用）
├── README.md                     # 本文件
├── include/nipaplay_native/
│   ├── nipaplay_native.h         # 统一 C API 入口头文件
│   ├── types.h                   # 跨平台基础类型定义
│   └── export.h                  # DLL 导出宏
├── src/
│   ├── nipaplay_native.cpp       # C API thunk 实现（异常安全边界）
│   ├── string_utils.cpp          # NpString 辅助函数
│   └── example_calculator.cpp    # 示例模块实现
├── modules/
│   └── example_calculator.h      # 示例模块 C++ 头文件
└── scripts/
    ├── build_ios.sh              # iOS 静态库编译脚本
    └── build_macos.sh            # macOS dylib 编译脚本
```

Dart 侧绑定位于 `lib/cpp_native/`。

## 添加新模块

1. 在 `modules/` 下创建 `my_module.h`（纯 C++20 类）
2. 在 `src/` 下创建 `my_module.cpp`（实现）
3. 在 `include/nipaplay_native/nipaplay_native.h` 中添加 `extern "C"` API 声明
4. 在 `src/nipaplay_native.cpp` 中添加 thunk 实现（**必须** try-catch 包裹）
5. 在 `CMakeLists.txt` 的 `NATIVE_SOURCES` 列表中添加新 .cpp
6. 在 `lib/cpp_native/bindings/` 下创建对应 Dart 封装
7. 在 `lib/cpp_native/nipaplay_native.dart` 中导出

## 命名规范

- C API 函数：`np_<module>_<verb>`（如 `np_example_add`）
- C 类型：`Np` 前缀（如 `NpHandle`, `NpString`, `NpResult`）
- Dart 封装类：PascalCase（如 `ExampleCalculator`）
- 与 Rust 链路符号隔离：Rust 用 `next2_`/`sim_` 前缀

## 平台支持

| 平台 | 编译工具 | 产物格式 | Dart 加载方式 |
|------|---------|---------|-------------|
| Windows | MSVC (CMake) | `.dll` | `DynamicLibrary.open` |
| Linux | GCC/Clang (CMake) | `.so` | `DynamicLibrary.open` |
| macOS | Clang (CMake/Xcode) | `.dylib` | `DynamicLibrary.open` |
| iOS | Clang (Xcode) | `.a` 静态库 | `DynamicLibrary.process` |
| Android | NDK (CMake) | `.so` per ABI | `DynamicLibrary.open` |

- **Web 不支持**（dart:ffi 在 Web 不可用）
- **HarmonyOS 留作后续扩展**

## 注意事项

- C++ 异常禁止跨越 FFI 边界 — Thunk 层必须 catch-all
- `NpHandle` 使用 `void*`，Dart 侧禁止截断为 `int32`
- armeabi-v7a 兼容：`Pointer<Void>` 自动适配 4 字节指针
- MSVC 统一使用 `/MD`（动态 CRT），与 Flutter 引擎一致
- Android 使用 `c++_shared` STL，与 Flutter 引擎一致

## 编译选项

> 所有编译选项均使用 **target 作用域**（`target_compile_options` / `target_compile_definitions`），
> 不会泄漏到父级或其他子项目。跨平台属性在 `add_library` 之前设置为全局默认值，
> CMake 自动根据编译器匹配正确的 flag。

### 跨平台属性（CMake 自动适配）

| 属性 | 说明 | 自动生成 flag |
|------|------|--------------|
| `CMAKE_POSITION_INDEPENDENT_CODE ON` | 位置无关代码 | GCC/Clang → `-fPIC`，MSVC → 无需处理 |
| `CMAKE_CXX_VISIBILITY_PRESET hidden` | 符号可见性隐藏 | GCC/Clang → `-fvisibility=hidden`，MSVC → 不自动导出 |
| `CMAKE_VISIBILITY_INLINES_HIDDEN ON` | 内联函数符号隐藏 | GCC/Clang → `-fvisibility-inlines-hidden`，减小动态库体积 |
| `INTERPROCEDURAL_OPTIMIZATION_RELEASE` | Release LTO/IPO | GCC/Clang → `-flto`，MSVC → `/GL + /LTCG` |

LTO/IPO 启用前使用 `CheckIPOSupported` 模块检测编译器支持情况，不支持时发出警告而非硬失败。

### 公共编译定义

| 定义 | 说明 |
|------|------|
| `NIPAPLAY_NATIVE_BUILDING` | 标识库自身编译（区别于外部引用头文件），通过 `target_compile_definitions` 设置 |

### 平台特定编译选项

| 功能维度 | GCC / Clang | MSVC | 说明 |
|---------|-------------|------|------|
| **RTTI** | `-fno-rtti` | `/GR-` | 禁用运行时类型信息，减小二进制体积 |
| **异常** | `-fexceptions` | `/EHsc` | 显式启用异常（与 `/EHsc` 等价），防止外部全局 `-fno-exceptions` 覆盖 |
| **警告** | `-Wall -Wextra -Wpedantic` | `/W4` | 严格静态警告 |
| **字符集** | 默认 UTF-8 | `/utf-8` | 强制 MSVC 使用 UTF-8 |
| **`__cplusplus`** | 默认正确 | `/Zc:__cplusplus` | 使 MSVC 的 `__cplusplus` 宏正确反映 C++20 |

### 优化选项

| 构建模式 | GCC / Clang | MSVC |
|---------|-------------|------|
| **Debug** | `-Og` | `/Od`（默认） |
| **Release** | `-O3 -ffast-math`（等效 `-Ofast`） | `/O2 /Ob3 /fp:fast` |
| **Release LTO** | `-flto`（由 CMake 属性自动添加） | `/GL + /LTCG`（由 CMake 属性自动添加） |

- **Debug** 使用 `-Og`：保留完整调试信息与栈帧，优化调试体验而不完全禁用优化。
- **Release** 使用 `-O3 -ffast-math` / `/O2 /Ob3 /fp:fast`：最大化弹幕布局引擎的计算吞吐。MSVC `/Ob3` 启用激进内联，接近 GCC `-O3` 的内联行为。
- **Release LTO** 使用 `INTERPROCEDURAL_OPTIMIZATION_RELEASE`：CMake 跨平台属性，自动为各编译器匹配正确的 LTO/IPO flag。启用前通过 `CheckIPOSupported` 检测兼容性。

`-ffast-math` 包含 `-ffinite-math-only`，会使标准库的 `std::isnan` / `std::isinf` 失效。为此，弹幕布局引擎使用 **IEEE 754 位运算** 实现的 `np_isnan` / `np_isinf` 替代标准库调用，确保在快速浮点模式下 NaN / Inf 检测仍然正确。