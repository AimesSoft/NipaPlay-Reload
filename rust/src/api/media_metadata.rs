use regex::Regex;
use std::cmp::Ordering;
use std::collections::HashSet;
use std::sync::OnceLock;

const SUBTITLE_NOISE_TOKENS: &[&str] = &[
    "ass",
    "srt",
    "ssa",
    "sub",
    "sup",
    "subtitle",
    "subtitles",
    "subs",
    "caption",
    "captions",
    "cc",
    "sdh",
    "chs",
    "cht",
    "sc",
    "tc",
    "gb",
    "big5",
    "zh",
    "zho",
    "chi",
    "cn",
    "jp",
    "jpn",
    "eng",
    "english",
    "chsjpn",
    "chtjpn",
    "scjp",
    "tcjp",
    "bilingual",
    "default",
    "forced",
    "signs",
    "sign",
    "dialogue",
    "dialog",
    "简中",
    "繁中",
    "简体",
    "繁体",
    "中文",
    "字幕",
    "双语",
];

#[flutter_rust_bridge::frb(sync)]
pub fn media_base_name_without_extension(path_or_name: String) -> String {
    let trimmed = path_or_name.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let base = trimmed
        .rsplit(['/', '\\'])
        .find(|segment| !segment.is_empty())
        .unwrap_or(trimmed);
    match base.rfind('.') {
        Some(index) if index > 0 => base[..index].trim().to_string(),
        _ => base.trim().to_string(),
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn media_extract_anime_title_keyword(path_or_name: String) -> String {
    let mut name = media_base_name_without_extension(path_or_name);
    if name.is_empty() {
        return name;
    }

    name = regex(r"[._]+").replace_all(&name, " ").trim().to_string();
    name = strip_leading_group_tags(name);
    name = regex(r"(?:\s*(?:\[[^\]]*\]|【[^】]*】|\([^)]*\)|（[^）]*）))+\s*$")
        .replace_all(name.trim_end(), "")
        .trim()
        .to_string();
    for pattern in [
        r"(?i)\bS\d{1,2}E\d{1,3}\b",
        r"(?i)\bS\d{1,2}\b",
        r"(?i)\bEP\s*\d{1,3}\b",
        r"(?i)\bE\d{1,3}\b",
        r"第\s*\d{1,3}\s*[话話集期]",
        r"\d{1,3}\s*[话話集期]\b",
        r"[\[【]\s*\d{1,3}\s*[\]】]",
        r"(?:\s*[-_]\s*)\d{1,3}$",
    ] {
        name = regex(pattern).replace_all(&name, " ").to_string();
    }
    name = regex(r"[\[\]【】()（）{}]")
        .replace_all(&name, " ")
        .to_string();
    regex(r"\s+").replace_all(&name, " ").trim().to_string()
}

#[flutter_rust_bridge::frb(sync)]
pub fn natural_compare(a: String, b: String) -> i32 {
    let a_parts = natural_parts(&a);
    let b_parts = natural_parts(&b);
    for (left, right) in a_parts.iter().zip(&b_parts) {
        let ordering = if is_decimal(left) && is_decimal(right) {
            compare_decimal_strings(left, right).then_with(|| left.len().cmp(&right.len()))
        } else {
            cmp_utf16(&left.to_lowercase(), &right.to_lowercase())
        };
        if ordering != Ordering::Equal {
            return ordering_to_i32(ordering);
        }
    }
    ordering_to_i32(a_parts.len().cmp(&b_parts.len()))
}

/// Preserves the provider's older natural-sort behavior: text is case-sensitive
/// and equal numeric values do not use their zero-padding as a tiebreaker.
#[flutter_rust_bridge::frb(sync)]
pub fn natural_compare_case_sensitive(a: String, b: String) -> i32 {
    let a_parts = natural_parts(&a);
    let b_parts = natural_parts(&b);
    for (left, right) in a_parts.iter().zip(&b_parts) {
        let ordering = if is_decimal(left) && is_decimal(right) {
            compare_decimal_strings(left, right)
        } else {
            cmp_utf16(left, right)
        };
        if ordering != Ordering::Equal {
            return ordering_to_i32(ordering);
        }
    }
    ordering_to_i32(a_parts.len().cmp(&b_parts.len()))
}

#[flutter_rust_bridge::frb(sync)]
pub fn subtitle_normalize_match_name(name: String) -> String {
    subtitle_extract_match_tokens(name).join(" ")
}

#[flutter_rust_bridge::frb(sync)]
pub fn subtitle_extract_match_tokens(name: String) -> Vec<String> {
    let working = regex(r"[\[({][^\])}]*[\])}]")
        .replace_all(&name.to_lowercase(), " ")
        .to_string();
    let mut seen = HashSet::new();
    regex(r"[^a-z0-9\u{4e00}-\u{9fff}\u{3040}-\u{30ff}\u{ac00}-\u{d7af}]+")
        .split(&working)
        .map(str::trim)
        .filter(|token| !token.is_empty() && !is_subtitle_noise_token(token))
        .filter_map(|token| seen.insert(token.to_string()).then(|| token.to_string()))
        .collect()
}

#[flutter_rust_bridge::frb(sync)]
pub fn subtitle_pick_likely_episode_number(numbers: Vec<String>) -> Option<String> {
    numbers
        .iter()
        .find(|number| number.len() == 2 && number.parse::<i64>().is_ok_and(|value| value > 0))
        .cloned()
        .or_else(|| numbers.last().cloned())
}

#[flutter_rust_bridge::frb(sync)]
pub fn subtitle_compute_match_score(
    video_name: String,
    subtitle_name: String,
    extension: String,
    video_numbers: Vec<String>,
    episode_number: Option<String>,
) -> i32 {
    let lower_video = video_name.to_lowercase();
    let lower_subtitle = subtitle_name.to_lowercase();
    let normalized_video = subtitle_normalize_match_name(video_name.clone());
    let normalized_subtitle = subtitle_normalize_match_name(subtitle_name.clone());
    let mut score = match extension.to_lowercase().as_str() {
        ".ass" => 70,
        ".ssa" => 60,
        ".srt" => 50,
        ".sub" => 35,
        ".sup" => 20,
        _ => 0,
    };

    if lower_subtitle == lower_video {
        score += 500;
    }
    if [".", " ", "[", "("]
        .iter()
        .any(|suffix| lower_subtitle.starts_with(&format!("{lower_video}{suffix}")))
    {
        score += 320;
    }
    if !normalized_video.is_empty() && normalized_subtitle == normalized_video {
        score += 280;
    } else if !normalized_video.is_empty()
        && normalized_subtitle.starts_with(&format!("{normalized_video} "))
    {
        score += 220;
    } else if !normalized_video.is_empty() && normalized_subtitle.contains(&normalized_video) {
        score += 180;
    } else if !normalized_subtitle.is_empty() && normalized_video.contains(&normalized_subtitle) {
        score += 80;
    }

    let video_tokens = subtitle_extract_match_tokens(video_name);
    let subtitle_tokens: HashSet<String> = subtitle_extract_match_tokens(subtitle_name.clone())
        .into_iter()
        .collect();
    let overlap_count = video_tokens
        .iter()
        .filter(|token| subtitle_tokens.contains(*token))
        .count();
    score += overlap_count as i32 * 25;
    if !video_tokens.is_empty() && overlap_count == video_tokens.len() {
        score += 120;
    } else if video_tokens.len() >= 2 && overlap_count == 0 {
        score -= 80;
    }

    let subtitle_numbers: Vec<String> = regex(r"\d+")
        .find_iter(&subtitle_name)
        .map(|value| value.as_str().to_string())
        .collect();
    let subtitle_episode = subtitle_pick_likely_episode_number(subtitle_numbers.clone());
    match (episode_number, subtitle_episode) {
        (Some(video_episode), Some(subtitle_episode)) if video_episode == subtitle_episode => {
            score += 220;
        }
        (Some(video_episode), Some(subtitle_episode)) => {
            let video_value = video_episode.parse::<i64>().ok();
            let subtitle_value = subtitle_episode.parse::<i64>().ok();
            if video_value.is_some()
                && video_value == subtitle_value
                && video_value.is_some_and(|v| v > 0)
            {
                score += 190;
            } else {
                score -= 120;
            }
        }
        _ if !video_numbers.is_empty() && !subtitle_numbers.is_empty() => {
            for number in video_numbers.into_iter().take(3) {
                if subtitle_numbers.contains(&number) {
                    score += 15;
                }
            }
        }
        _ => {}
    }
    score
}

fn strip_leading_group_tags(mut value: String) -> String {
    loop {
        let trimmed = value.trim_start();
        let closing = if trimmed.starts_with('[') {
            Some(']')
        } else if trimmed.starts_with('【') {
            Some('】')
        } else {
            None
        };
        match closing.and_then(|character| trimmed.find(character).map(|index| (index, character)))
        {
            Some((index, character)) if index > 0 => {
                value = trimmed[index + character.len_utf8()..]
                    .trim_start()
                    .to_string()
            }
            _ => return trimmed.to_string(),
        }
    }
}

fn is_subtitle_noise_token(token: &str) -> bool {
    if SUBTITLE_NOISE_TOKENS.contains(&token) {
        return true;
    }
    if regex(r"^(?:\d{3,4}p|\d{3,4}x\d{3,4})$").is_match(token)
        || regex(r"^(?:x26[45]|h26[45]|hevc|av1|avc|aac\d*|flac|ac3|eac3|opus|truehd|dts|dtsx|atmos|hdr\d*|dv|uhd|remux|webdl|web|webrip|bluray|bdrip|10bit|8bit)$").is_match(token)
        || regex(r"^\d{3,4}$").is_match(token)
    {
        return true;
    }
    token.starts_with("zh") && token.len() <= 8
}

fn natural_parts(value: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut current = String::new();
    let mut current_is_digit: Option<bool> = None;
    for character in value.chars() {
        let is_digit = character.is_ascii_digit();
        if current_is_digit.is_some_and(|kind| kind != is_digit) {
            parts.push(std::mem::take(&mut current));
        }
        current.push(character);
        current_is_digit = Some(is_digit);
    }
    if !current.is_empty() {
        parts.push(current);
    }
    parts
}

fn is_decimal(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit())
}

fn compare_decimal_strings(left: &str, right: &str) -> Ordering {
    let left_value = left.trim_start_matches('0');
    let right_value = right.trim_start_matches('0');
    let left_value = if left_value.is_empty() {
        "0"
    } else {
        left_value
    };
    let right_value = if right_value.is_empty() {
        "0"
    } else {
        right_value
    };
    left_value
        .len()
        .cmp(&right_value.len())
        .then_with(|| left_value.as_bytes().cmp(right_value.as_bytes()))
}

fn cmp_utf16(left: &str, right: &str) -> Ordering {
    left.encode_utf16().cmp(right.encode_utf16())
}

fn ordering_to_i32(ordering: Ordering) -> i32 {
    match ordering {
        Ordering::Less => -1,
        Ordering::Equal => 0,
        Ordering::Greater => 1,
    }
}

fn regex(pattern: &'static str) -> &'static Regex {
    static REGEXES: OnceLock<
        std::sync::Mutex<std::collections::HashMap<&'static str, &'static Regex>>,
    > = OnceLock::new();
    let cache = REGEXES.get_or_init(Default::default);
    if let Some(value) = cache
        .lock()
        .expect("regex cache poisoned")
        .get(pattern)
        .copied()
    {
        return value;
    }
    let compiled = Box::leak(Box::new(Regex::new(pattern).expect("valid metadata regex")));
    cache
        .lock()
        .expect("regex cache poisoned")
        .insert(pattern, compiled);
    compiled
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_anime_title() {
        assert_eq!(
            media_extract_anime_title_keyword("[Group] My.Anime.S02E03.1080p.mkv".into()),
            "My Anime 1080p"
        );
    }

    #[test]
    fn compares_names_naturally() {
        assert_eq!(natural_compare("Episode 2".into(), "Episode 10".into()), -1);
        assert_eq!(
            natural_compare(
                "Episode 999999999999999999999".into(),
                "Episode 1000000000000000000000".into()
            ),
            -1
        );
        assert_eq!(
            natural_compare_case_sensitive("Season 02".into(), "Season 2".into()),
            0
        );
    }

    #[test]
    fn scores_matching_subtitle() {
        let score = subtitle_compute_match_score(
            "Anime 02".into(),
            "Anime 02.chs".into(),
            ".ass".into(),
            vec!["02".into()],
            Some("02".into()),
        );
        assert!(score >= 100);
    }
}
