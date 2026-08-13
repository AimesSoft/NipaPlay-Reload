use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

type SyncState = BTreeMap<String, BTreeMap<String, Value>>;

#[derive(Clone, Debug)]
pub struct RustSyncBlob {
    pub bytes: Vec<u8>,
    pub sha256: String,
}

#[derive(Clone, Debug)]
pub struct RustSyncPatchInput {
    pub bytes: Vec<u8>,
    pub expected_sha256: String,
    pub expected_id: String,
}

#[derive(Clone, Debug)]
pub struct RustSyncPatchChainResult {
    pub state_json: Vec<u8>,
    pub applied_patch_ids: Vec<String>,
}

#[derive(Clone, Debug)]
pub struct RustSyncDecodedSnapshot {
    pub state_json: Vec<u8>,
    pub sha256: String,
}

#[derive(Clone, Debug)]
pub struct RustBackupRestorePlan {
    pub version: i64,
    pub timestamp: String,
    pub app_version: String,
    pub preferences_json: Vec<u8>,
    pub media_libraries_json: Vec<u8>,
    pub accounts_json: Vec<u8>,
    pub watch_history_batches: Vec<Vec<u8>>,
    pub episode_match_batches: Vec<Vec<u8>>,
    pub invalid_watch_history_count: i64,
    pub invalid_episode_match_count: i64,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct SyncOperation {
    category: String,
    key: String,
    deleted: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    value: Option<Value>,
    modified_at: String,
    device_id: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SyncPatch {
    format_version: i64,
    id: String,
    snapshot_version: i64,
    #[allow(dead_code)]
    created_at: String,
    #[allow(dead_code)]
    device_id: String,
    operations: Vec<SyncOperation>,
}

/// Parses arbitrary JSON and emits the stable, key-sorted encoding used by
/// incremental sync v1. Keeping this in Rust avoids building a second Dart
/// object graph just for canonicalization and hashing.
pub fn sync_canonicalize_json(input: Vec<u8>, pretty: bool) -> Result<RustSyncBlob, String> {
    let value: Value = serde_json::from_slice(&input).map_err(json_error)?;
    let bytes = if pretty {
        serde_json::to_vec_pretty(&value).map_err(json_error)?
    } else {
        serde_json::to_vec(&value).map_err(json_error)?
    };
    Ok(RustSyncBlob {
        sha256: sha256_hex(&bytes),
        bytes,
    })
}

pub fn sync_sha256_bytes(input: Vec<u8>) -> String {
    sha256_hex(&input)
}

/// Parses a full backup exactly once, keeps only the requested categories and
/// emits large record collections as bounded JSON batches. This avoids
/// materializing the entire `.npb` object graph in Dart before restoration.
pub fn backup_prepare_restore(
    input: Vec<u8>,
    include_preferences: bool,
    include_media_libraries: bool,
    include_watch_history: bool,
    include_episode_matches: bool,
    include_accounts: bool,
    batch_size: i64,
) -> Result<RustBackupRestorePlan, String> {
    let root: Value = serde_json::from_slice(&input).map_err(json_error)?;
    let object = root
        .as_object()
        .ok_or_else(|| "备份文件根节点必须是 JSON 对象".to_owned())?;
    let version = object.get("version").and_then(Value::as_i64).unwrap_or(0);
    if version > 2 {
        return Err(format!("不支持的备份格式版本: {version}"));
    }
    let actual_batch_size = batch_size.clamp(1, 2_000) as usize;

    let preferences_json = selected_object_bytes(object, "preferences", include_preferences)?;
    let media_libraries_json =
        selected_object_bytes(object, "mediaLibraries", include_media_libraries)?;
    let accounts_json = selected_object_bytes(object, "accounts", include_accounts)?;

    let (watch_history_batches, invalid_watch_history_count) = if include_watch_history {
        normalize_array_batches(
            object.get("watchHistory"),
            actual_batch_size,
            normalize_watch_history_record,
        )?
    } else {
        (Vec::new(), 0)
    };
    let (episode_match_batches, invalid_episode_match_count) = if include_episode_matches {
        normalize_array_batches(
            object.get("episodeMatches"),
            actual_batch_size,
            normalize_episode_match_record,
        )?
    } else {
        (Vec::new(), 0)
    };

    Ok(RustBackupRestorePlan {
        version,
        timestamp: object
            .get("timestamp")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned(),
        app_version: object
            .get("appVersion")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned(),
        preferences_json,
        media_libraries_json,
        accounts_json,
        watch_history_batches,
        episode_match_batches,
        invalid_watch_history_count,
        invalid_episode_match_count,
    })
}

/// Builds an entity-level diff between two flattened sync states.
pub fn sync_diff_states(
    previous_json: Vec<u8>,
    current_json: Vec<u8>,
    modified_at: String,
    device_id: String,
) -> Result<Vec<u8>, String> {
    let previous: SyncState = serde_json::from_slice(&previous_json).map_err(json_error)?;
    let current: SyncState = serde_json::from_slice(&current_json).map_err(json_error)?;
    let mut operations = Vec::new();
    let categories: BTreeSet<&String> = previous.keys().chain(current.keys()).collect();

    for category in categories {
        let before = previous.get(category);
        let after = current.get(category);
        let keys: BTreeSet<&String> = before
            .into_iter()
            .flat_map(|values| values.keys())
            .chain(after.into_iter().flat_map(|values| values.keys()))
            .collect();
        for key in keys {
            match (
                before.and_then(|values| values.get(key)),
                after.and_then(|values| values.get(key)),
            ) {
                (Some(_), None) => operations.push(SyncOperation {
                    category: category.clone(),
                    key: key.clone(),
                    deleted: true,
                    value: None,
                    modified_at: modified_at.clone(),
                    device_id: device_id.clone(),
                }),
                (old, Some(new)) if old != Some(new) => operations.push(SyncOperation {
                    category: category.clone(),
                    key: key.clone(),
                    deleted: false,
                    value: Some(new.clone()),
                    modified_at: modified_at.clone(),
                    device_id: device_id.clone(),
                }),
                _ => {}
            }
        }
    }

    serde_json::to_vec(&operations).map_err(json_error)
}

pub fn sync_apply_operations(
    state_json: Vec<u8>,
    operations_json: Vec<u8>,
) -> Result<Vec<u8>, String> {
    let mut state: SyncState = serde_json::from_slice(&state_json).map_err(json_error)?;
    let operations: Vec<SyncOperation> =
        serde_json::from_slice(&operations_json).map_err(json_error)?;
    apply_operations(&mut state, operations);
    serde_json::to_vec(&state).map_err(json_error)
}

/// Verifies and decodes a snapshot while keeping the large state payload as
/// UTF-8 bytes. Dart only needs to materialize that state once, after all
/// remote patches have been replayed.
pub fn sync_decode_snapshot_state(
    snapshot_bytes: Vec<u8>,
    expected_sha256: String,
    expected_repository_id: String,
    expected_snapshot_version: i64,
) -> Result<RustSyncDecodedSnapshot, String> {
    let actual_hash = sha256_hex(&snapshot_bytes);
    if !expected_sha256.is_empty() && actual_hash != expected_sha256 {
        return Err("远端同步对象校验失败".to_owned());
    }
    let snapshot: Value = serde_json::from_slice(&snapshot_bytes).map_err(json_error)?;
    let repository_id = snapshot
        .get("repositoryId")
        .and_then(Value::as_str)
        .ok_or_else(|| "基准快照缺少 repositoryId".to_owned())?;
    let snapshot_version = snapshot
        .get("snapshotVersion")
        .and_then(Value::as_i64)
        .ok_or_else(|| "基准快照缺少 snapshotVersion".to_owned())?;
    if repository_id != expected_repository_id || snapshot_version != expected_snapshot_version {
        return Err("基准快照与 manifest.version 不匹配".to_owned());
    }
    let state = snapshot
        .get("state")
        .ok_or_else(|| "基准快照缺少 state".to_owned())?;
    let state_json = serde_json::to_vec(state).map_err(json_error)?;
    Ok(RustSyncDecodedSnapshot {
        state_json,
        sha256: actual_hash,
    })
}

/// Validates and replays an ordered patch chain without sending every decoded
/// operation through the FFI boundary.
pub fn sync_apply_patch_chain(
    state_json: Vec<u8>,
    patches: Vec<RustSyncPatchInput>,
    maximum_snapshot_version: i64,
) -> Result<RustSyncPatchChainResult, String> {
    let mut state: SyncState = serde_json::from_slice(&state_json).map_err(json_error)?;
    let mut applied_patch_ids = Vec::new();

    for input in patches {
        let actual_hash = sha256_hex(&input.bytes);
        if !input.expected_sha256.is_empty() && actual_hash != input.expected_sha256 {
            return Err("远端同步对象校验失败".to_owned());
        }
        let patch: SyncPatch = serde_json::from_slice(&input.bytes).map_err(json_error)?;
        if patch.format_version != 1 {
            return Err(format!("不支持的补丁版本: {}", patch.format_version));
        }
        if !input.expected_id.is_empty() && patch.id != input.expected_id {
            return Err("补丁索引与文件内容不匹配".to_owned());
        }
        if patch.snapshot_version > maximum_snapshot_version {
            continue;
        }
        apply_operations(&mut state, patch.operations);
        applied_patch_ids.push(patch.id);
    }

    Ok(RustSyncPatchChainResult {
        state_json: serde_json::to_vec(&state).map_err(json_error)?,
        applied_patch_ids,
    })
}

fn apply_operations(state: &mut SyncState, operations: Vec<SyncOperation>) {
    for operation in operations {
        let values = state.entry(operation.category).or_default();
        if operation.deleted {
            values.remove(&operation.key);
        } else if let Some(value) = operation.value {
            values.insert(operation.key, value);
        }
    }
}

fn selected_object_bytes(
    root: &serde_json::Map<String, Value>,
    key: &str,
    selected: bool,
) -> Result<Vec<u8>, String> {
    if !selected {
        return Ok(Vec::new());
    }
    match root.get(key) {
        Some(value) if value.is_object() => serde_json::to_vec(value).map_err(json_error),
        Some(_) => Err(format!("备份字段 {key} 必须是 JSON 对象")),
        None => Ok(Vec::new()),
    }
}

fn normalize_array_batches(
    value: Option<&Value>,
    batch_size: usize,
    normalize: fn(&Value) -> Option<Value>,
) -> Result<(Vec<Vec<u8>>, i64), String> {
    let Some(value) = value else {
        return Ok((Vec::new(), 0));
    };
    let values = value
        .as_array()
        .ok_or_else(|| "备份记录集合必须是 JSON 数组".to_owned())?;
    if values.is_empty() {
        return Ok((vec![b"[]".to_vec()], 0));
    }
    let mut normalized = Vec::with_capacity(batch_size.min(values.len()));
    let mut batches = Vec::new();
    let mut invalid_count = 0;
    for value in values {
        if let Some(record) = normalize(value) {
            normalized.push(record);
            if normalized.len() == batch_size {
                batches.push(serde_json::to_vec(&normalized).map_err(json_error)?);
                normalized.clear();
            }
        } else {
            invalid_count += 1;
        }
    }
    if !normalized.is_empty() {
        batches.push(serde_json::to_vec(&normalized).map_err(json_error)?);
    }
    Ok((batches, invalid_count))
}

fn normalize_watch_history_record(value: &Value) -> Option<Value> {
    let source = value.as_object()?;
    let file_path = source.get("filePath")?.as_str()?.trim();
    if file_path.is_empty() {
        return None;
    }
    let last_watch_time = source.get("lastWatchTime")?.as_str()?.trim();
    if last_watch_time.is_empty() {
        return None;
    }
    let anime_name = source
        .get("animeName")
        .and_then(Value::as_str)
        .filter(|name| !name.is_empty())
        .unwrap_or(file_path);
    let mut record = serde_json::Map::new();
    record.insert("filePath".to_owned(), Value::String(file_path.to_owned()));
    record.insert("animeName".to_owned(), Value::String(anime_name.to_owned()));
    copy_optional_string(source, &mut record, "episodeTitle");
    copy_optional_i64(source, &mut record, "episodeId");
    copy_optional_i64(source, &mut record, "animeId");
    record.insert(
        "watchProgress".to_owned(),
        Value::from(
            source
                .get("watchProgress")
                .and_then(Value::as_f64)
                .unwrap_or(0.0),
        ),
    );
    record.insert(
        "lastPosition".to_owned(),
        Value::from(value_as_i64(source.get("lastPosition")).unwrap_or(0)),
    );
    record.insert(
        "duration".to_owned(),
        Value::from(value_as_i64(source.get("duration")).unwrap_or(0)),
    );
    record.insert(
        "lastWatchTime".to_owned(),
        Value::String(last_watch_time.to_owned()),
    );
    record.insert(
        "isFromScan".to_owned(),
        Value::Bool(
            source
                .get("isFromScan")
                .and_then(Value::as_bool)
                .unwrap_or(false),
        ),
    );
    copy_optional_string(source, &mut record, "videoHash");
    copy_optional_string(source, &mut record, "thumbnailBase64");
    Some(Value::Object(record))
}

fn normalize_episode_match_record(value: &Value) -> Option<Value> {
    let source = value.as_object()?;
    let file_path = source.get("filePath")?.as_str()?.trim();
    let anime_id = value_as_i64(source.get("animeId"))?;
    let episode_id = value_as_i64(source.get("episodeId"))?;
    if file_path.is_empty() {
        return None;
    }
    let mut record = serde_json::Map::new();
    record.insert("filePath".to_owned(), Value::String(file_path.to_owned()));
    record.insert("animeId".to_owned(), Value::from(anime_id));
    record.insert("episodeId".to_owned(), Value::from(episode_id));
    copy_optional_string(source, &mut record, "animeName");
    copy_optional_string(source, &mut record, "episodeTitle");
    copy_optional_string(source, &mut record, "videoHash");
    Some(Value::Object(record))
}

fn value_as_i64(value: Option<&Value>) -> Option<i64> {
    let value = value?;
    value
        .as_i64()
        .or_else(|| value.as_f64().map(|number| number as i64))
}

fn copy_optional_i64(
    source: &serde_json::Map<String, Value>,
    target: &mut serde_json::Map<String, Value>,
    key: &str,
) {
    if let Some(value) = value_as_i64(source.get(key)) {
        target.insert(key.to_owned(), Value::from(value));
    }
}

fn copy_optional_string(
    source: &serde_json::Map<String, Value>,
    target: &mut serde_json::Map<String, Value>,
    key: &str,
) {
    if let Some(value) = source.get(key).and_then(Value::as_str) {
        target.insert(key.to_owned(), Value::String(value.to_owned()));
    }
}

fn sha256_hex(input: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h = [
        0x6a09e667u32,
        0xbb67ae85,
        0x3c6ef372,
        0xa54ff53a,
        0x510e527f,
        0x9b05688c,
        0x1f83d9ab,
        0x5be0cd19,
    ];
    let mut data = input.to_vec();
    let bit_len = (data.len() as u64) * 8;
    data.push(0x80);
    while data.len() % 64 != 56 {
        data.push(0);
    }
    data.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in data.chunks_exact(64) {
        let mut w = [0u32; 64];
        for (index, word) in chunk.chunks_exact(4).take(16).enumerate() {
            w[index] = u32::from_be_bytes([word[0], word[1], word[2], word[3]]);
        }
        for index in 16..64 {
            let s0 = w[index - 15].rotate_right(7)
                ^ w[index - 15].rotate_right(18)
                ^ (w[index - 15] >> 3);
            let s1 = w[index - 2].rotate_right(17)
                ^ w[index - 2].rotate_right(19)
                ^ (w[index - 2] >> 10);
            w[index] = w[index - 16]
                .wrapping_add(s0)
                .wrapping_add(w[index - 7])
                .wrapping_add(s1);
        }

        let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut hh] = h;
        for index in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[index])
                .wrapping_add(w[index]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);
            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }
        for (target, value) in h.iter_mut().zip([a, b, c, d, e, f, g, hh].into_iter()) {
            *target = target.wrapping_add(value);
        }
    }
    h.iter().map(|value| format!("{value:08x}")).collect()
}

fn json_error(error: serde_json::Error) -> String {
    error.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_json_sorts_nested_object_keys() {
        let result = sync_canonicalize_json(br#"{"b":2,"a":{"y":2,"x":1}}"#.to_vec(), false)
            .expect("canonical JSON");
        assert_eq!(
            String::from_utf8(result.bytes).expect("UTF-8"),
            r#"{"a":{"x":1,"y":2},"b":2}"#
        );
    }

    #[test]
    fn diff_and_apply_reconstruct_target_state() {
        let before = br#"{"preferences":{"same":true,"changed":1,"deleted":"old"}}"#;
        let after = br#"{"preferences":{"same":true,"changed":2,"inserted":"new"}}"#;
        let operations = sync_diff_states(
            before.to_vec(),
            after.to_vec(),
            "2026-08-13T00:00:00Z".to_owned(),
            "device-a".to_owned(),
        )
        .expect("diff");
        let rebuilt = sync_apply_operations(before.to_vec(), operations).expect("apply");
        let rebuilt_value: Value = serde_json::from_slice(&rebuilt).expect("rebuilt JSON");
        let after_value: Value = serde_json::from_slice(after).expect("target JSON");
        assert_eq!(rebuilt_value, after_value);
    }

    #[test]
    fn full_backup_restore_plan_filters_normalizes_and_batches() {
        let input = br#"{
          "version":2,
          "preferences":{"settings":{"theme":"dark"}},
          "watchHistory":[
            {"filePath":"/a.mkv","animeName":"A","lastWatchTime":"2026-08-13T00:00:00Z","episodeId":1.0},
            {"filePath":"","lastWatchTime":"2026-08-13T00:00:00Z"},
            {"filePath":"/b.mkv","animeName":"B","lastWatchTime":"2026-08-13T00:00:01Z"}
          ],
          "episodeMatches":[
            {"filePath":"/a.mkv","animeId":10.0,"episodeId":1},
            {"filePath":"/bad.mkv","animeId":10}
          ]
        }"#;
        let plan = backup_prepare_restore(input.to_vec(), true, false, true, true, false, 1)
            .expect("restore plan");
        assert_eq!(plan.version, 2);
        assert_eq!(plan.watch_history_batches.len(), 2);
        assert_eq!(plan.invalid_watch_history_count, 1);
        assert_eq!(plan.episode_match_batches.len(), 1);
        assert_eq!(plan.invalid_episode_match_count, 1);
        assert!(!plan.preferences_json.is_empty());
        assert!(plan.accounts_json.is_empty());
        let first: Value = serde_json::from_slice(&plan.watch_history_batches[0]).unwrap();
        assert_eq!(first[0]["episodeId"], 1);
    }
}
