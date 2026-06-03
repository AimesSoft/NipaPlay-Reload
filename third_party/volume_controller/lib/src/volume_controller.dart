import 'dart:async';

import 'package:flutter/services.dart';
import 'package:volume_controller/src/constants.dart';

/// Provides access to the system volume.
class VolumeController {
  /// Singleton instance of VolumeController
  static final VolumeController _instance = VolumeController._();

  /// Get the singleton instance of VolumeController
  static VolumeController get instance => _instance;

  /// Method channel for communicating with platform methods.
  final MethodChannel _methodChannel = MethodChannel(ChannelName.methodChannel);

  /// Event channel for communicating with platform events.
  final EventChannel _eventChannel = EventChannel(ChannelName.eventChannel);

  /// Volume listener subscription
  StreamSubscription<double>? _volumeListener;

  /// Whether to show the system UI when changing the volume.
  bool showSystemUI = true;

  /// Private constructor for singleton
  VolumeController._();

  /// Adds a listener for volume changes.
  ///
  /// This method listens to the system volume. The volume value will be generated when the volume changes.
  /// Optionally, the initial volume can be fetched and provided to the listener immediately.
  StreamSubscription<double> addListener(
    Function(double)? onData, {
    bool fetchInitialVolume = true,
  }) {
    if (_volumeListener != null) {
      removeListener();
    }

    _volumeListener = _eventChannel
        .receiveBroadcastStream({
          EventArgument.fetchInitialVolume: fetchInitialVolume,
        })
        .map((d) => d as double)
        .listen(onData);

    return _volumeListener!;
  }

  /// Cancels the volume listener.
  ///
  /// This method stops listening to volume changes and cleans up the listener.
  void removeListener() {
    _volumeListener?.cancel();
    _volumeListener = null;
  }

  /// Gets the current system volume.
  ///
  /// This method retrieves the current volume level of the system.
  Future<double> getVolume() async {
    return await _methodChannel
        .invokeMethod<double>(MethodName.getVolume)
        .then<double>((double? value) => value ?? 0);
  }

  /// Sets the system volume to the specified level.
  ///
  /// This method sets the system volume to the given level. The volume
  /// value should be a double between 0.0 (minimum volume) and 1.0 (maximum volume).
  Future<void> setVolume(double volume) async {
    await _methodChannel.invokeMethod(MethodName.setVolume, {
      MethodArgument.volume: volume,
      MethodArgument.showSystemUI: showSystemUI,
    });
  }

  /// Gets the current system volume mute status.
  Future<bool> isMuted() async {
    return await _methodChannel
        .invokeMethod<bool>(MethodName.isMuted)
        .then<bool>((value) => value!);
  }

  /// Sets the system volume mute status.
  Future<void> setMute(bool mute) async {
    await _methodChannel.invokeMethod(MethodName.setMute, {
      MethodArgument.isMute: mute,
      MethodArgument.showSystemUI: showSystemUI,
    });
  }
}
