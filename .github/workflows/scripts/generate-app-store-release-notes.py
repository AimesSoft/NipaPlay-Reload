#!/usr/bin/env python3
"""Generate localized App Store release notes from the GitHub release notes."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import sys
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


DEFAULT_MAX_CHARACTERS = 4000
DEFAULT_MAX_ATTEMPTS = 5


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--zh-locale", default="zh-Hans")
    parser.add_argument("--en-locale", default="en-US")
    parser.add_argument("--max-characters", type=int, default=DEFAULT_MAX_CHARACTERS)
    parser.add_argument("--max-attempts", type=int, default=DEFAULT_MAX_ATTEMPTS)
    return parser.parse_args()


def required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"{name} is required")
    return value


def character_count(text: str) -> int:
    """Use the larger of Unicode code points and UTF-16 code units."""
    utf16_units = len(text.encode("utf-16-le")) // 2
    return max(len(text), utf16_units)


def normalize_response(content: str) -> str:
    content = content.replace("\r\n", "\n").replace("\r", "\n").strip()
    fenced = re.fullmatch(r"```(?:text|markdown)?\s*\n?(.*?)\n?```", content, re.DOTALL)
    if fenced:
        content = fenced.group(1).strip()
    return content


def extract_content(response: dict[str, Any]) -> str:
    try:
        content = response["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as error:
        raise RuntimeError("AI response does not contain choices[0].message.content") from error

    if isinstance(content, str):
        return normalize_response(content)
    if isinstance(content, list):
        text_parts = [part.get("text", "") for part in content if isinstance(part, dict)]
        return normalize_response("".join(text_parts))
    raise RuntimeError("AI response content is not text")


def call_ai(api_url: str, api_token: str, model: str, prompt: str) -> str:
    payload = json.dumps(
        {
            "model": model,
            "temperature": 0.3,
            "stream": False,
            "messages": [{"role": "user", "content": prompt}],
        },
        ensure_ascii=False,
    ).encode("utf-8")

    request = Request(
        api_url,
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_token}",
            "Content-Type": "application/json; charset=utf-8",
        },
    )

    last_error: Exception | None = None
    for request_attempt in range(1, 4):
        try:
            with urlopen(request, timeout=180) as response:
                body = response.read().decode("utf-8")
            return extract_content(json.loads(body))
        except HTTPError as error:
            last_error = error
            if error.code not in {408, 429, 500, 502, 503, 504}:
                detail = error.read().decode("utf-8", errors="replace")[:1000]
                raise RuntimeError(f"AI request failed with HTTP {error.code}: {detail}") from error
        except (URLError, TimeoutError, json.JSONDecodeError) as error:
            last_error = error

        if request_attempt < 3:
            delay = 5 * request_attempt
            print(f"AI request failed; retrying in {delay} seconds...", file=sys.stderr)
            time.sleep(delay)

    raise RuntimeError(f"AI request failed after retries: {last_error}")


def initial_prompt(language: str, source: str, max_characters: int) -> str:
    if language == "zh":
        language_rules = """
请使用简体中文。把内容编辑成 App Store“此版本的新功能”文案。
""".strip()
    else:
        language_rules = """
Write in natural US English. Translate and edit the source into App Store “What's New” copy.
""".strip()

    return f"""
You are the release-note editor for NipaPlay, a cross-platform video player.
{language_rules}

Requirements:
- Return only the final release-note text.
- The result must be no more than {max_characters} characters; aim for no more than 3600.
- Use plain text only. Do not use Markdown headings, links, URLs, code fences, or emoji.
- Short bullet lines using “•” are allowed.
- Keep only user-visible new features, improvements, and fixes.
- Remove contributors, pull request numbers, issue numbers, CI/build/release-process details, dependency maintenance, and internal refactors.
- Do not invent features or fixes that are absent from the source.
- Make the result concise and suitable for an App Store product page.

Source GitHub release notes:
---
{source}
---
""".strip()


def shorten_prompt(language: str, previous: str, current_count: int, max_characters: int) -> str:
    language_instruction = "继续使用简体中文。" if language == "zh" else "Continue in natural US English."
    return f"""
The following App Store release notes are {current_count} characters long and exceed the {max_characters}-character limit.
{language_instruction}
Rewrite and shorten them to no more than {max_characters} characters; aim for no more than 3600.
Preserve the most important user-visible features and fixes.
Return only plain text, with no Markdown headings, links, URLs, code fences, emoji, contributor names, or internal maintenance details.

Text to shorten:
---
{previous}
---
""".strip()


def generate_language(
    language: str,
    source: str,
    api_url: str,
    api_token: str,
    model: str,
    max_characters: int,
    max_attempts: int,
) -> str:
    prompt = initial_prompt(language, source, max_characters)
    for attempt in range(1, max_attempts + 1):
        result = call_ai(api_url, api_token, model, prompt)
        count = character_count(result)
        print(f"{language} App Store notes attempt {attempt}: {count} characters")

        if result and count <= max_characters:
            return result

        if not result:
            prompt = initial_prompt(language, source, max_characters)
        else:
            prompt = shorten_prompt(language, result, count, max_characters)

    raise RuntimeError(
        f"Unable to generate {language} App Store notes within {max_characters} characters "
        f"after {max_attempts} attempts"
    )


def write_metadata(output_dir: Path, locale: str, content: str) -> Path:
    locale_dir = output_dir / locale
    locale_dir.mkdir(parents=True, exist_ok=True)
    path = locale_dir / "release_notes.txt"
    path.write_text(content.rstrip(), encoding="utf-8")
    return path


def main() -> int:
    args = parse_args()
    source = args.source.read_text(encoding="utf-8").strip()
    if not source:
        raise RuntimeError("GitHub release notes are empty; refusing to submit empty App Store notes")

    api_url = required_env("AI_API_URL")
    api_token = required_env("AI_API_TOKEN")
    model = required_env("AI_MODEL")

    zh_notes = generate_language(
        "zh", source, api_url, api_token, model, args.max_characters, args.max_attempts
    )
    en_notes = generate_language(
        "en", source, api_url, api_token, model, args.max_characters, args.max_attempts
    )

    zh_path = write_metadata(args.output_dir, args.zh_locale, zh_notes)
    en_path = write_metadata(args.output_dir, args.en_locale, en_notes)

    summary = {
        args.zh_locale: {"path": str(zh_path), "characters": character_count(zh_notes)},
        args.en_locale: {"path": str(en_path), "characters": character_count(en_notes)},
    }
    (args.output_dir / "release-notes-summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
