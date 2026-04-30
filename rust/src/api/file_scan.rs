use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Instant;

pub struct RustFileScanEntry {
    pub relative_path: String,
    pub absolute_path: String,
    pub size: i64,
    pub modified_millis: i64,
    pub file_hash: String,
}

pub struct RustFileScanSnapshot {
    pub folder_hash: String,
    pub files: Vec<RustFileScanEntry>,
}

pub struct RustFileScanDiff {
    pub current_count: i32,
    pub cached_count: i32,
    pub current_files: Vec<String>,
    pub new_files: Vec<String>,
    pub modified_files: Vec<String>,
    pub deleted_files: Vec<String>,
    pub folder_hash: String,
    pub current_hashes: Vec<RustFileHashEntry>,
}

pub struct RustFileHashEntry {
    pub relative_path: String,
    pub hash: String,
}

#[flutter_rust_bridge::frb(sync)]
pub fn is_rust_file_scan_available() -> bool {
    true
}

pub fn scan_video_files(folder_path: String) -> Result<RustFileScanSnapshot, String> {
    let started_at = Instant::now();
    println!("[nipaplay_rust_scan] scan_video_files start path={folder_path}");

    let root = PathBuf::from(&folder_path);
    ensure_existing_directory(&root)?;

    let mut files = Vec::new();
    collect_video_files(&root, &root, &mut files)?;
    files.sort_by(|a, b| a.relative_path.cmp(&b.relative_path));

    let folder_hash = calculate_folder_hash(&files);
    println!(
        "[nipaplay_rust_scan] scan_video_files finish path={} files={} elapsed_ms={}",
        folder_path,
        files.len(),
        started_at.elapsed().as_millis()
    );
    Ok(RustFileScanSnapshot { folder_hash, files })
}

pub fn diff_video_files(
    folder_path: String,
    cached_hashes: Vec<RustFileHashEntry>,
) -> Result<RustFileScanDiff, String> {
    let started_at = Instant::now();
    let cached_count = cached_hashes.len();
    println!(
        "[nipaplay_rust_scan] diff_video_files start path={} cached_hashes={}",
        folder_path, cached_count
    );

    let snapshot = scan_video_files(folder_path.clone())?;
    let current_hashes: Vec<RustFileHashEntry> = snapshot
        .files
        .iter()
        .map(|entry| RustFileHashEntry {
            relative_path: entry.relative_path.clone(),
            hash: entry.file_hash.clone(),
        })
        .collect();

    let cached_map: HashMap<String, String> = cached_hashes
        .iter()
        .map(|entry| (entry.relative_path.clone(), entry.hash.clone()))
        .collect();
    let current_map: HashMap<String, String> = current_hashes
        .iter()
        .map(|entry| (entry.relative_path.clone(), entry.hash.clone()))
        .collect();

    let mut current_files: Vec<String> = current_map.keys().cloned().collect();
    current_files.sort();

    let mut new_files = Vec::new();
    let mut modified_files = Vec::new();
    for entry in &current_hashes {
        match cached_map.get(&entry.relative_path) {
            None => new_files.push(entry.relative_path.clone()),
            Some(cached_hash) if cached_hash != &entry.hash => {
                modified_files.push(entry.relative_path.clone())
            }
            _ => {}
        }
    }

    let current_paths: HashSet<&str> = current_hashes
        .iter()
        .map(|entry| entry.relative_path.as_str())
        .collect();
    let mut deleted_files: Vec<String> = cached_hashes
        .iter()
        .filter(|entry| !current_paths.contains(entry.relative_path.as_str()))
        .map(|entry| entry.relative_path.clone())
        .collect();

    new_files.sort();
    modified_files.sort();
    deleted_files.sort();

    println!(
        "[nipaplay_rust_scan] diff_video_files finish path={} current={} cached={} new={} modified={} deleted={} elapsed_ms={}",
        folder_path,
        current_hashes.len(),
        cached_count,
        new_files.len(),
        modified_files.len(),
        deleted_files.len(),
        started_at.elapsed().as_millis()
    );

    Ok(RustFileScanDiff {
        current_count: current_hashes.len() as i32,
        cached_count: cached_count as i32,
        current_files,
        new_files,
        modified_files,
        deleted_files,
        folder_hash: snapshot.folder_hash,
        current_hashes,
    })
}

fn ensure_existing_directory(path: &Path) -> Result<(), String> {
    match fs::metadata(path) {
        Ok(metadata) if metadata.is_dir() => Ok(()),
        Ok(_) => Err(format!("Path is not a directory: {}", path.display())),
        Err(error) => Err(format!(
            "Directory does not exist or cannot be read: {} ({error})",
            path.display()
        )),
    }
}

fn collect_video_files(
    root: &Path,
    current: &Path,
    output: &mut Vec<RustFileScanEntry>,
) -> Result<(), String> {
    let entries = match fs::read_dir(current) {
        Ok(entries) => entries,
        Err(error) => {
            return Err(format!(
                "Failed to read directory {}: {error}",
                current.display()
            ))
        }
    };

    for entry_result in entries {
        let entry = match entry_result {
            Ok(entry) => entry,
            Err(_) => continue,
        };
        let path = entry.path();
        let file_type = match entry.file_type() {
            Ok(file_type) => file_type,
            Err(_) => continue,
        };

        if file_type.is_symlink() {
            continue;
        }
        if file_type.is_dir() {
            collect_video_files(root, &path, output)?;
            continue;
        }
        if !file_type.is_file() || !is_video_file(&path) {
            continue;
        }

        if let Some(scan_entry) = make_scan_entry(root, &path) {
            output.push(scan_entry);
        }
    }

    Ok(())
}

fn make_scan_entry(root: &Path, path: &Path) -> Option<RustFileScanEntry> {
    let metadata = fs::metadata(path).ok()?;
    let modified_millis = metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0);
    let relative_path = path
        .strip_prefix(root)
        .ok()
        .map(path_to_dart_string)
        .unwrap_or_else(|| path_to_dart_string(path));
    let absolute_path = path_to_dart_string(path);
    let size = metadata.len().min(i64::MAX as u64) as i64;
    let file_info = format!("{}|{}", size, modified_millis);
    let file_hash = sha256_hex(file_info.as_bytes())[..16].to_string();

    Some(RustFileScanEntry {
        relative_path,
        absolute_path,
        size,
        modified_millis,
        file_hash,
    })
}

fn is_video_file(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .map(|extension| {
            let extension = extension.to_ascii_lowercase();
            extension == "mp4" || extension == "mkv"
        })
        .unwrap_or(false)
}

fn calculate_folder_hash(files: &[RustFileScanEntry]) -> String {
    let combined = files
        .iter()
        .map(|entry| {
            format!(
                "{}|{}|{}",
                entry.absolute_path, entry.size, entry.modified_millis
            )
        })
        .collect::<Vec<_>>()
        .join("\n");
    sha256_hex(combined.as_bytes())
}

fn path_to_dart_string(path: &Path) -> String {
    path.to_string_lossy().to_string()
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

    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];

    let bit_len = (input.len() as u64) * 8;
    let mut data = input.to_vec();
    data.push(0x80);
    while (data.len() % 64) != 56 {
        data.push(0);
    }
    data.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in data.chunks(64) {
        let mut w = [0u32; 64];
        for (i, word) in chunk.chunks(4).take(16).enumerate() {
            w[i] = u32::from_be_bytes([word[0], word[1], word[2], word[3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let mut a = h[0];
        let mut b = h[1];
        let mut c = h[2];
        let mut d = h[3];
        let mut e = h[4];
        let mut f = h[5];
        let mut g = h[6];
        let mut hh = h[7];

        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
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

        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    h.iter().map(|value| format!("{value:08x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::{self, File};
    use std::io::Write;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn sha256_matches_known_vectors() {
        assert_eq!(
            sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn diff_detects_new_modified_and_deleted_video_files() {
        let root = make_temp_dir();
        let keep_path = root.join("keep.mkv");
        let new_path = root.join("new.mp4");
        write_file(&keep_path, b"old");
        write_file(&new_path, b"new");

        let snapshot = scan_video_files(path_to_dart_string(&root)).unwrap();
        let keep_entry = snapshot
            .files
            .iter()
            .find(|entry| entry.relative_path == "keep.mkv")
            .unwrap();

        let diff = diff_video_files(
            path_to_dart_string(&root),
            vec![
                RustFileHashEntry {
                    relative_path: "keep.mkv".to_string(),
                    hash: "stale".to_string(),
                },
                RustFileHashEntry {
                    relative_path: "deleted.mp4".to_string(),
                    hash: keep_entry.file_hash.clone(),
                },
            ],
        )
        .unwrap();

        assert_eq!(diff.current_count, 2);
        assert_eq!(diff.cached_count, 2);
        assert_eq!(diff.new_files, vec!["new.mp4"]);
        assert_eq!(diff.modified_files, vec!["keep.mkv"]);
        assert_eq!(diff.deleted_files, vec!["deleted.mp4"]);

        let _ = fs::remove_dir_all(root);
    }

    fn make_temp_dir() -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "nipaplay_rust_file_scan_test_{}_{}",
            std::process::id(),
            nanos
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn write_file(path: &Path, bytes: &[u8]) {
        let mut file = File::create(path).unwrap();
        file.write_all(bytes).unwrap();
        file.sync_all().unwrap();
    }
}
