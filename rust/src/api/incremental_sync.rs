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
}
