import 'package:nipa_harness/nipa_harness.dart';

/// Domain semantics for describe-family; live ActionSpecs remain authoritative.
const catalogFamilyDescriptions = <String, String>{
  'media':
      'Files, local catalog, identity, metadata and artwork are independent facts. Local-only works use entities.put_batch without fabricated provider IDs. Catalog hierarchy is work → release → episode, with indexed fileIds on episodes. Batches declare atomicity. Changing/removing catalog associations requires a revision/impact preview and retains files, progress, prior facts and source audit. Removed local entities can be restored using undoId. Text and artwork clear reveal source facts and retain edit history; clearing an override is not deleting a disk file.',
  'media.entities':
      'Local catalog entities have stable caller-supplied IDs and expectedRevision on update. parentId is an actual local parent, never an external ID. fileIds on an episode replace its local associations. Removal includes descendants, retains tombstones and exact relationship before-images, and returns undoId; restore refuses subsequent conflicting changes. These operations do not manufacture Classic platform matches.',
  'subtitle':
      'Per-file subtitle facts persist independently from playback. Imports copy content into managed storage and batch errors retain index and recovery information. update edits imported language/title/source with expectedRevision; remove releases an imported association and retains its copy. reset_selection restores automatic selection; select null explicitly disables. Current internal playback and persistent selection use the same facts. copy_delete alone deletes unreferenced managed copies and returns NeedsDecision with an exact fingerprint. cues reads active external timed text with delay-aware current/context lines; embedded or bitmap limitations are explicit.',
  'playback':
      'open/pause/seek/navigation accept commands; snapshots observe asynchronously. State reports sessionId, readiness, buffering, buffered position, error/recovery and actual supported controls. External unknown position/duration/pause/rate remain null. wait is bounded and detects a changed session; retry explicitly reloads the source through Classic and may preserve position. chapters exposes container markers and detected skip segments; navigate uses chapter, frame or active skip semantics. Backward frame stepping may be approximate. playlist reports the actual detail source list, without authenticated stream URLs.',
  'danmaku':
      'entries reads the active merged/filtered display timeline around current time or an interval, including global offset and available provenance. Pagination can require expectedListVersion. It describes data supplied to the renderer, not pixel visibility; raw bound content remains available via export.',
};

JsonMap? describeCatalogFamily(String family, Iterable<ActionSpec> specs) {
  final description = catalogFamilyDescriptions[family];
  if (description == null) return null;
  return {
    'family': family,
    'description': description,
    'actions': [
      for (final spec in specs)
        if (spec.id.startsWith('$family.'))
          {
            'id': spec.id,
            'description': spec.description,
            'effect': spec.effect.name,
            'input': spec.input.toJsonSchema(),
            'output': spec.output.toJsonSchema(),
          }
    ]
  };
}
