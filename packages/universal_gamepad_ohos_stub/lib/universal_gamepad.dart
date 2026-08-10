import 'dart:async';

/// No-op HarmonyOS replacement for the native universal_gamepad plugin.
///
/// HarmonyOS has no implementation of the plugin. Keeping this small API
/// surface lets shared NipaPlay sources compile without registering a native
/// plugin or opening a platform channel.
final class Gamepad {
  Gamepad._();

  static final Gamepad instance = Gamepad._();

  Stream<GamepadEvent> get events => const Stream<GamepadEvent>.empty();

  Stream<GamepadConnectionEvent> get connectionEvents =>
      const Stream<GamepadConnectionEvent>.empty();

  Stream<GamepadButtonEvent> get buttonEvents =>
      const Stream<GamepadButtonEvent>.empty();

  Stream<GamepadAxisEvent> get axisEvents =>
      const Stream<GamepadAxisEvent>.empty();

  Future<List<GamepadInfo>> listGamepads() async => const <GamepadInfo>[];

  Future<void> dispose() async {}

  Future<void> pause() async {}

  Future<void> resume() async {}
}

sealed class GamepadEvent {
  const GamepadEvent({
    required this.gamepadId,
    required this.timestamp,
  });

  final int gamepadId;
  final int timestamp;
}

final class GamepadConnectionEvent extends GamepadEvent {
  const GamepadConnectionEvent({
    required super.gamepadId,
    required super.timestamp,
    required this.connected,
    required this.info,
  });

  final bool connected;
  final GamepadInfo info;
}

final class GamepadButtonEvent extends GamepadEvent {
  const GamepadButtonEvent({
    required super.gamepadId,
    required super.timestamp,
    required this.button,
    required this.pressed,
    required this.value,
  });

  final GamepadButton button;
  final bool pressed;
  final double value;
}

final class GamepadAxisEvent extends GamepadEvent {
  const GamepadAxisEvent({
    required super.gamepadId,
    required super.timestamp,
    required this.axis,
    required this.value,
  });

  final GamepadAxis axis;
  final double value;
}

final class GamepadInfo {
  const GamepadInfo({
    required this.id,
    required this.name,
    this.vendorId,
    this.productId,
  });

  final int id;
  final String name;
  final int? vendorId;
  final int? productId;
}

enum GamepadButton {
  a,
  b,
  x,
  y,
  leftShoulder,
  rightShoulder,
  leftTrigger,
  rightTrigger,
  back,
  start,
  leftStickButton,
  rightStickButton,
  dpadUp,
  dpadDown,
  dpadLeft,
  dpadRight,
  guide,
}

enum GamepadAxis {
  leftStickX,
  leftStickY,
  rightStickX,
  rightStickY,
}
