import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../media/media_service.dart';
import '../ui_data/service.dart';
import 'service.dart';

/// The same composition for the GUI and the headless host: commits are
/// serialized with the other identity writers, and what read the changed rows
/// is told afterwards.
///
/// Nothing here is a cache of its own. Merged metadata is computed per read;
/// the artwork cache, the mesh library index and the interface observe
/// `total_changes()` and refresh by fingerprint, so this only makes that
/// happen now instead of at the next poll.
DbService createDbService(
    {required Database database,
    required MediaService media,
    required UiDataService uiData}) {
  final service = DbService(database, serialize: media.mutate);
  service.afterCommit = (summary) async {
    final refreshed = <String>[];
    final artwork = {
      ...?summary.entities['artwork'],
      ...?summary.entities['metadata']
    };
    // Images are fetched on demand; start the ones whose source just changed
    // so they are ready when the work is next shown.
    for (final id in summary.entities['artwork']?.take(5) ?? const <String>[]) {
      // Best effort: a source that cannot be fetched shows as missing artwork.
      unawaited(uiData.artwork.load(id).then<void>((_) {}, onError: (_) {}));
    }
    if (artwork.isNotEmpty) refreshed.add('artwork_cache');
    final mesh = uiData.meshLibrary;
    if (mesh != null) {
      await mesh.prepareIndex();
      refreshed.add('mesh_library_index');
    }
    uiData.notifyLibraryChanged();
    refreshed.add('ui_data');
    return refreshed;
  };
  return service;
}
