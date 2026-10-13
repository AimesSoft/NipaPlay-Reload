const appFamilyDescription =
    'Live host facts: app.instance identifies the process; '
    'app.capabilities reports supported features, provider/source readiness, '
    'credential references and required host setup, settings keys, action effects '
    'and remote policy. supported means an implementation exists; available means '
    'its declared host prerequisites are met, not a successful network probe. '
    'No secrets are accepted or returned. Remote writes follow local semantics; '
    'disk deletion/overwrite keep their existing NeedsDecision contract. '
    'On headless hosts indexing and download destinations treat media roots as '
    'read-only; file-channel operations use actual process permissions. '
    'A headless host has no Classic history/player/UI. download.import indexes verified files '
    'without inferring identity; roots.remove unregisters the root without deleting '
    'indexed facts or disk files. settings exposes only returned keys.';

const danmakuFamilyDescription =
    'Persistent danmaku sources, caches and tracks. '
    'Both GUI and headless use the same NipaPlay Dandanplay gateway/client, '
    'host vault reference preferences/dandanplay_token and local import parser. '
    'sources reports installed adapters; app.capabilities reports credential readiness. '
    'Headless prepares persisted tracks without mounting a player; supply entityId '
    'or path because current playback is absent. Metadata identity, acquisition '
    'and binding are independent facts. Empty title/hash results mean no source '
    'candidate, not a broken host. A successful fetch task proves acquisition; '
    'an existing track alone does not. fetch_batch, attach_batch and import_batch '
    'accept 1–100 entries matching the single action schema, validate all schemas '
    'first, then return input index and complete outcome for every entry. '
    'atomic=false; failure retains earlier committed results. Credentials never '
    'enter inputs. Task/binding IDs and per-item decisions/errors are preserved. '
    'align/align_apply/align_keep are legacyRecovery; new analysis uses '
    'analyze_alignment and update. Positive offsetMs advances comments: '
    'displayTime=sourceTime-offsetMs. Headless exports are under data/exports.';

const capabilityFamilyDescriptions = {
  'app': appFamilyDescription,
  'danmaku': danmakuFamilyDescription,
};
