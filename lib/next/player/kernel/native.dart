import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart'
    show PlayerUpscalerMode;

/// A value as the kernel gave it, or the kernel's own error.
typedef NativeRead = ({String? value, String? error});

/// What a kernel instance answers to a command or a method.
typedef NativeReply = ({Object? result, String? error});
typedef NativeInvokeReply = ({Object? result, String? error, bool supported});

/// What `playback.kernel` and the rest read of a kernel instance and change
/// in it. The instance hands out this and nothing else of itself (I3):
/// every call runs behind its fence (I2) and, but for a command that takes
/// long, in its queue (I8). A call on an instance that is released throws
/// [KernelFenced].
abstract interface class KernelNative {
  /// The kernel library's own version, as the kernel gives it (null: none).
  Future<Object?> version();

  /// The kernel's own answer to each of [names].
  Future<Map<String, NativeRead>> read(List<String> names);
}

/// Media Kit: mpv's properties and commands.
abstract interface class MpvNative implements KernelNative {
  /// Sets an mpv property now, for what plays. mpv's error, or null.
  Future<String?> write(String name, String value);

  /// Runs an mpv command as given.
  Future<NativeReply> command(List<String> args, {Duration timeout});

  /// Has mpv write its full log to [path] (empty stops).
  Future<void> logFile(String path);
}

/// MDK: its player properties and decoder lists.
abstract interface class MdkNative implements KernelNative {
  Future<void> write(String name, String value);
  Future<List<String>> decoders({required bool video});
  Future<void> setDecoders(List<String> names, {required bool video});

  /// The decoder MDK opened for the media (null: none reported).
  Future<String?> activeDecoder({required bool video});
}

/// Erika: its own status, its method table, upscaler and debug HUD.
abstract interface class ErikaNative implements KernelNative {
  Future<JsonMap> status();
  Future<NativeInvokeReply> invoke(String method, JsonMap arguments);
  Future<PlayerUpscalerMode> upscaler();
  Future<void> setUpscaler(PlayerUpscalerMode mode);
  Future<bool> debugHud();
  Future<void> setDebugHud(bool enabled);

  /// Entries of Erika's process-wide log from [sinceSeq] on (null: none).
  Future<Map<String, Object?>?> engineLog({int? sinceSeq});
}

/// A kernel that tells its own state by name (video_player's controller
/// value), with no properties to set.
abstract interface class StateNative implements KernelNative {
  List<String> get names;
}

/// A kernel with nothing to read or change beyond what playback does.
final class PlainNative implements KernelNative {
  const PlainNative(this._version);
  final String? _version;
  @override
  Future<Object?> version() async => _version;
  @override
  Future<Map<String, NativeRead>> read(List<String> names) async => {
        for (final name in names)
          name: (value: null, error: 'This kernel reports no properties.')
      };
}
