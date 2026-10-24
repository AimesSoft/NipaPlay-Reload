import 'driver.dart';

/// The track on the new kernel that stands for one that was on in the old:
/// the one track with the same language, title (and codec, where both say),
/// else the same index when both kernels list as many tracks; null with the
/// reason when there is none. A kernel that names its tracks differently
/// does not match by guess.
({int? index, String? reason}) matchTrack(
    List<TrackFacts> before, int? active, List<TrackFacts> now) {
  if (active == null) return (index: null, reason: null);
  final chosen = before.where((t) => t.index == active).firstOrNull;
  if (chosen == null) return (index: null, reason: null);
  final same = [
    for (final t in now)
      if (t.language == chosen.language &&
          t.title == chosen.title &&
          (chosen.codec == null || t.codec == null || t.codec == chosen.codec))
        t.index
  ];
  if (same.length == 1) return (index: same.single, reason: null);
  if (now.length == before.length && active < now.length) {
    return (index: active, reason: null);
  }
  return (index: null, reason: 'no_matching_track');
}
