/// Web stub for ExampleCalculator.
///
/// Provides the same public API as [example_calculator_io.dart] (renamed from
/// example_calculator.dart) without any `dart:ffi` / `package:ffi` imports,
/// so it compiles on Web. On Web this class is never actually used.

import '../types/native_types_web.dart';
import '../types/native_result_web.dart';

class ExampleCalculator {
  ExampleCalculator();

  int add(int a, int b) => throw UnsupportedError(
      'ExampleCalculator is not available on Web');

  NativeResult<String> processText(String input) =>
      throw UnsupportedError('ExampleCalculator is not available on Web');

  void dispose() {}
}
