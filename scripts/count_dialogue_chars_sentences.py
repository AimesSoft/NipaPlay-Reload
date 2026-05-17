#!/usr/bin/env python3
import argparse
import re
from pathlib import Path

# Match speaker tags like lg, lg2, ls, ls2 at line start.
SPEAKER_RE = re.compile(r'^\s*(lg\d*|ls\d*)\b(.*)$', re.IGNORECASE)
# Handle malformed merged tags like "lslg..." seen in some script lines.
MALFORMED_MERGED_TAG_RE = re.compile(r'^\s*(lslg|lgls)\s*(.*)$', re.IGNORECASE)

# Remove inline comments and common script control tokens.
COMMENT_RE = re.compile(r'\s*##.*$|\s*#.*$')
CONTROL_TOKEN_RE = re.compile(r'//[a-zA-Z0-9_]+')
BRACE_TAG_RE = re.compile(r'\{[^{}]*\}')

# Chinese + English sentence ending punctuation.
SENT_END_RE = re.compile(r'[。！？!?；;…]+')

TARGETS = {
    'lg': '李宫娜',
    'ls': '刘守真',
}


def extract_dialogue_text(rest: str) -> str:
    """Extract dialogue text from a line remainder after speaker tag."""
    text = COMMENT_RE.sub('', rest).strip()

    # If quoted, take the first quoted segment as dialogue body.
    first_quote = text.find('"')
    if first_quote != -1:
        second_quote = text.find('"', first_quote + 1)
        if second_quote != -1:
            text = text[first_quote + 1:second_quote]
        else:
            text = text[first_quote + 1:]

    # Normalize and strip control syntax.
    text = CONTROL_TOKEN_RE.sub('', text)
    text = BRACE_TAG_RE.sub('', text)
    text = text.replace('\\n', '')
    text = text.replace('//n', '')
    text = text.strip()
    return text


def count_chars(text: str) -> int:
    # Count visible chars excluding whitespace.
    return len(re.sub(r'\s+', '', text))


def count_sentences(text: str) -> int:
    stripped = text.strip()
    if not stripped:
        return 0
    ends = SENT_END_RE.findall(stripped)
    if ends:
        return len(ends)
    # No explicit punctuation but still a spoken line.
    return 1


def main() -> None:
    parser = argparse.ArgumentParser(
        description='Count total characters and sentences for 李宫娜/刘守真 in script file.'
    )
    parser.add_argument('file', type=Path, help='Script file path')
    args = parser.parse_args()

    stats = {
        'lg': {'lines': 0, 'chars': 0, 'sentences': 0},
        'ls': {'lines': 0, 'chars': 0, 'sentences': 0},
    }

    with args.file.open('r', encoding='utf-8') as f:
        for raw in f:
            line = raw.rstrip('\n')
            m = SPEAKER_RE.match(line)
            if m:
                speaker_tag = m.group(1).lower()
                base = 'lg' if speaker_tag.startswith('lg') else 'ls'
                rest = m.group(2)
            else:
                # If both tags are accidentally concatenated, pick the first one.
                merged = MALFORMED_MERGED_TAG_RE.match(line)
                if not merged:
                    continue
                merged_tag = merged.group(1).lower()
                base = 'ls' if merged_tag.startswith('ls') else 'lg'
                rest = merged.group(2)
            text = extract_dialogue_text(rest)
            if not text:
                continue

            stats[base]['lines'] += 1
            stats[base]['chars'] += count_chars(text)
            stats[base]['sentences'] += count_sentences(text)

    total_chars = stats['lg']['chars'] + stats['ls']['chars']
    total_sentences = stats['lg']['sentences'] + stats['ls']['sentences']
    total_lines = stats['lg']['lines'] + stats['ls']['lines']

    print(f"李宫娜: 台词行数={stats['lg']['lines']} 字数={stats['lg']['chars']} 句数={stats['lg']['sentences']}")
    print(f"刘守真: 台词行数={stats['ls']['lines']} 字数={stats['ls']['chars']} 句数={stats['ls']['sentences']}")
    print(f"合计: 台词行数={total_lines} 字数={total_chars} 句数={total_sentences}")


if __name__ == '__main__':
    main()
