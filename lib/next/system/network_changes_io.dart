/// 无 Flutter 方法通道的宿主使用前台兼容检查。
abstract final class SystemNetworkChanges {
  static Stream<void>? get changes => null;
}
