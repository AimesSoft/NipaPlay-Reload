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
