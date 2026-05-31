/// NipaPlay 原生 C++-Dart FFI 框架
///
/// 提供通过 dart:ffi 直接调用 C++20 原生模块的能力。
/// 此链路（Link C）与现有 Rust 链路（Link A/B）完全独立。
///
/// 用法：
/// ```dart
/// import 'package:nipaplay/cpp_native/nipaplay_native.dart';
///
/// final calc = ExampleCalculator();
/// print(calc.add(3, 4)); // 7
/// print(calc.processText('hello')); // [NpNative] HELLO
/// calc.dispose();
/// ```
library;

export 'bindings/example_calculator.dart';
export 'bindings/similarity_engine.dart';
export 'types/native_result.dart';
export 'types/native_types.dart';
