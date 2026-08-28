use std::cmp::Ordering;

use super::media_metadata::natural_ordering;

const PRESET_DEFAULT: i32 = 0;
const PRESET_NAME_ASC: i32 = 1;
const PRESET_NAME_DESC: i32 = 2;
const PRESET_MODIFIED_DESC: i32 = 3;
const PRESET_MODIFIED_ASC: i32 = 4;
const PRESET_SIZE_DESC: i32 = 5;
const PRESET_SIZE_ASC: i32 = 6;

/// Sorts a complete remote directory in one Rust task and returns the original
/// indices in display order. Keeping the payload columnar avoids creating a
/// second remote-file model across the FFI boundary.
pub fn sort_remote_entry_indices(
    names: Vec<String>,
    is_directories: Vec<bool>,
    sizes: Vec<i64>,
    modified_millis: Vec<i64>,
    preset: i32,
) -> Result<Vec<u32>, String> {
    let entry_count = names.len();
    if is_directories.len() != entry_count
        || sizes.len() != entry_count
        || modified_millis.len() != entry_count
    {
        return Err("Remote directory sort columns have different lengths".to_string());
    }
    if entry_count > u32::MAX as usize {
        return Err("Remote directory contains too many entries".to_string());
    }
    if !(PRESET_DEFAULT..=PRESET_SIZE_ASC).contains(&preset) {
        return Err(format!("Unknown remote directory sort preset: {preset}"));
    }

    let mut indices: Vec<usize> = (0..entry_count).collect();
    indices.sort_by(|&left, &right| {
        compare_entries(
            left,
            right,
            &names,
            &is_directories,
            &sizes,
            &modified_millis,
            preset,
        )
    });
    Ok(indices.into_iter().map(|index| index as u32).collect())
}

fn compare_entries(
    left: usize,
    right: usize,
    names: &[String],
    is_directories: &[bool],
    sizes: &[i64],
    modified_millis: &[i64],
    preset: i32,
) -> Ordering {
    match preset {
        PRESET_DEFAULT => is_directories[right]
            .cmp(&is_directories[left])
            .then_with(|| natural_ordering(&names[left], &names[right])),
        PRESET_NAME_ASC => natural_ordering(&names[left], &names[right]),
        PRESET_NAME_DESC => natural_ordering(&names[right], &names[left]),
        PRESET_MODIFIED_DESC => modified_millis[right]
            .cmp(&modified_millis[left])
            .then_with(|| natural_ordering(&names[left], &names[right])),
        PRESET_MODIFIED_ASC => modified_millis[left]
            .cmp(&modified_millis[right])
            .then_with(|| natural_ordering(&names[left], &names[right])),
        PRESET_SIZE_DESC => sizes[right]
            .cmp(&sizes[left])
            .then_with(|| natural_ordering(&names[left], &names[right])),
        PRESET_SIZE_ASC => sizes[left]
            .cmp(&sizes[right])
            .then_with(|| natural_ordering(&names[left], &names[right])),
        _ => Ordering::Equal,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sort(names: &[&str], directories: &[bool], preset: i32) -> Vec<u32> {
        sort_remote_entry_indices(
            names.iter().map(|name| (*name).to_string()).collect(),
            directories.to_vec(),
            vec![0; names.len()],
            vec![0; names.len()],
            preset,
        )
        .expect("valid sort input")
    }

    #[test]
    fn default_sort_keeps_directories_first_and_uses_natural_names() {
        let order = sort(
            &["Episode 10.mkv", "Season 10", "Episode 2.mkv", "Season 2"],
            &[false, true, false, true],
            PRESET_DEFAULT,
        );
        assert_eq!(order, vec![3, 1, 2, 0]);
    }

    #[test]
    fn metadata_sort_uses_natural_name_as_tie_breaker() {
        let order = sort_remote_entry_indices(
            vec!["Episode 10".into(), "Episode 2".into(), "Episode 1".into()],
            vec![false; 3],
            vec![0; 3],
            vec![100, 100, 200],
            PRESET_MODIFIED_DESC,
        )
        .expect("valid sort input");
        assert_eq!(order, vec![2, 1, 0]);
    }

    #[test]
    fn rejects_mismatched_columns() {
        let result = sort_remote_entry_indices(
            vec!["Episode 1".into()],
            vec![],
            vec![0],
            vec![0],
            PRESET_DEFAULT,
        );
        assert!(result.is_err());
    }
}
