import 'ui_data.dart';

/// Optional facade so older UI test doubles need not implement subscriptions.
abstract interface class NextSubscriptionsData {
  Stream<List<UiSubscription>> subscriptions({String? deviceId});
}

extension SubscriptionUiData on NextUiData {
  /// All owners by default, or one owner's device ID. Calls on a remote
  /// subscription use [UiSubscription.id] on [UiSubscription.deviceId].
  Stream<List<UiSubscription>> subscriptions({String? deviceId}) =>
      this is NextSubscriptionsData
          ? (this as NextSubscriptionsData).subscriptions(deviceId: deviceId)
          : Stream.value(const []);
}

enum UiSubscriptionState { active, paused, ended }

final class UiSubscriptionDownload {
  const UiSubscriptionDownload(
      {required this.jobId, required this.title, this.episode});
  final String jobId, title;
  final String? episode;
}

final class UiSubscription {
  const UiSubscription(
      {required this.id,
      required this.title,
      required this.state,
      required this.deviceId,
      this.device,
      this.online = true,
      this.workId,
      this.artwork,
      this.note = '',
      this.kind = 'series',
      this.lastCheckedAt,
      this.downloads = const [],
      this.errors = const []});

  /// Original entity ID on the owner, never a fabricated merged ID.
  final String id, title, deviceId, note, kind;
  final UiSubscriptionState state;

  /// null for this device.
  final String? device;
  final bool online;
  final String? workId;
  final UiArtwork? artwork;
  final DateTime? lastCheckedAt;
  final List<UiSubscriptionDownload> downloads;
  final List<String> errors;
}
