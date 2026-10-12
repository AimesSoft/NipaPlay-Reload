import 'package:nipa_harness/nipa_harness.dart';
import 'classic_metadata_port.dart';
import 'identity_store.dart';

final class ClassicProjection {
  const ClassicProjection(this.store, this.port);
  final IdentityStore store;
  final ClassicMetadataPort port;
  Future<void> drain({String? fileId}) async {
    await store.importLegacy(await port.history());
    for (final row in await store.pendingProjections(fileId: fileId)) {
      final file = await store.entity(row['file_id'] as String);
      if (file['revision'] != row['file_revision'] ||
          (file['attributes'] as JsonMap)['bindingRevision'] !=
              row['binding_revision']) {
        await store.finishProjection(row['id'] as String, 'superseded');
        continue;
      }
      final fields = decodeMediaJson(row['payload']);
      try {
        for (final location in (await store.locations(row['file_id'] as String))
            .where((location) =>
                location['owner_device_id'] == store.ownerDeviceId)) {
          final observations = await store
              .classicObservations(row['file_id'] as String, currentOnly: true);
          final atLocation =
              observations.where((o) => o['locationId'] == location['id']);
          final current =
              atLocation.isEmpty ? <String, Object?>{} : atLocation.single;
          if (port is! ReversibleClassicMetadataPort &&
              fields['clear'] != true &&
              current['animeName'] != null &&
              current['animeName'] != '' &&
              current['episodeTitle'] != null &&
              current['animeId'] != null &&
              current['episodeId'] != null &&
              (current['animeId'] !=
                      (fields['animeId'] ?? fields['expectedAnimeId']) ||
                  current['episodeId'] !=
                      (fields['episodeId'] ?? fields['expectedEpisodeId']))) {
            throw const Failure(FailureCode.conflict,
                'Classic has a different match; inspect media.identity.get conflicts.');
          }
          final delivery = {...fields, 'projectionId': row['id']};
          await port.apply(location['locator'] as String, delivery);
          if (!await port.verify(location['locator'] as String, delivery)) {
            throw const Failure(FailureCode.unavailable,
                'Classic metadata projection failed readback.');
          }
        }
        await store.finishProjection(row['id'] as String, 'delivered');
      } on Failure catch (error) {
        if (error.code == FailureCode.conflict) {
          await store.finishProjection(row['id'] as String, 'conflict');
        }
        rethrow;
      }
    }
    await store.importLegacy(await port.history());
  }
}
