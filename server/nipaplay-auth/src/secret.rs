use std::time::Duration;

use reqwest::Client;
use serde_json::Value;
use tracing::warn;

use crate::env_value;

/// Loads the Dandanplay AppSecret from the environment, falling back to the
/// legacy bootstrap endpoints used by older deployments.
pub async fn load_app_secret(user_agent: &str) -> Result<String, String> {
    if let Ok(secret) = std::env::var("DANDANPLAY_APP_SECRET") {
        let secret = secret.trim().to_owned();
        if !secret.is_empty() {
            return Ok(secret);
        }
    }

    let urls = env_value(
        "DANDANPLAY_APP_SECRET_URLS",
        "https://kurisu.aimes-soft.com/nipaplay.php,https://nipaplay.aimes-soft.com/nipaplay.php",
    );
    let client = Client::builder()
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(10))
        .user_agent(user_agent)
        .build()
        .map_err(|error| format!("failed to create bootstrap client: {error}"))?;

    for url in urls.split(',').map(str::trim).filter(|url| !url.is_empty()) {
        let result = async {
            let response = client
                .get(url)
                .send()
                .await
                .map_err(|error| error.to_string())?
                .error_for_status()
                .map_err(|error| error.to_string())?;
            let payload: Value = response.json().await.map_err(|error| error.to_string())?;
            let encrypted = payload
                .get("encryptedAppSecret")
                .and_then(Value::as_str)
                .filter(|value| !value.is_empty())
                .ok_or_else(|| "missing encryptedAppSecret".to_owned())?;
            Ok::<String, String>(decode_legacy_secret(encrypted))
        }
        .await;

        match result {
            Ok(secret) if !secret.is_empty() => return Ok(secret),
            Ok(_) => warn!(url, "legacy AppSecret endpoint returned an empty secret"),
            Err(error) => warn!(url, %error, "failed to load AppSecret from legacy endpoint"),
        }
    }

    Err("DANDANPLAY_APP_SECRET is missing and all legacy secret endpoints failed".to_owned())
}

/// Decodes the obfuscated AppSecret returned by the legacy bootstrap endpoints.
pub fn decode_legacy_secret(input: &str) -> String {
    let mut chars: Vec<char> = input
        .chars()
        .map(|character| match character {
            'A'..='Z' => char::from_u32('A' as u32 + 25 - (character as u32 - 'A' as u32)).unwrap(),
            'a'..='z' => char::from_u32('a' as u32 + 25 - (character as u32 - 'a' as u32)).unwrap(),
            _ => character,
        })
        .collect();

    if chars.len() >= 5 {
        let first = chars.remove(0);
        let insertion = chars.len().saturating_sub(4);
        chars.insert(insertion, first);
    }

    chars
        .into_iter()
        .map(|character| {
            if let Some(digit) = character.to_digit(10) {
                char::from_u32('0' as u32 + (10 - digit)).unwrap_or(character)
            } else if character.is_ascii_lowercase() {
                character.to_ascii_uppercase()
            } else if character.is_ascii_uppercase() {
                character.to_ascii_lowercase()
            } else {
                character
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legacy_secret_applies_the_documented_transforms() {
        // Short inputs: alphabet reversal, then case swap.
        assert_eq!(decode_legacy_secret("ab"), "ZY");
        // Digits become their 10's complement.
        assert_eq!(decode_legacy_secret("1"), "9");
        // Five or more characters also rotate the first character to the end.
        assert_eq!(decode_legacy_secret("abcde"), "ZYXWV");
    }
}
