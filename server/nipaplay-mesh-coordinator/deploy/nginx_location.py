#!/usr/bin/env python3
"""Adds or removes the /mesh/ location in an nginx site file.

  nginx_location.py add    <site.conf> <nginx-location.conf>   -> prints the new file to stdout
  nginx_location.py remove <site.conf>                         -> prints the new file to stdout

The block goes right after the closing brace of `location ^~ /dandanplay/ {`
and is wrapped in marker comments so it can be removed exactly. Nothing is
written to the site file: the caller diffs, tests and then installs.
"""
import sys

BEGIN = "    # >>> nipaplay-mesh (deploy/nginx-location.conf) >>>"
END = "    # <<< nipaplay-mesh <<<"


def find_block_end(text: str, start: int) -> int:
    depth = 0
    i = text.index("{", start)
    while i < len(text):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise SystemExit("unbalanced braces after the /dandanplay/ location")


def add(site: str, block: str) -> str:
    if BEGIN in site or "location ^~ /mesh/" in site:
        raise SystemExit("the site file already has a /mesh/ location")
    marker = "location ^~ /dandanplay/"
    if site.count(marker) != 1:
        raise SystemExit(f"expected exactly one '{marker}' in the site file")
    end = find_block_end(site, site.index(marker))
    # keep the rest of the line (usually a newline) after the inserted block
    body = "\n".join(
        ("    " + line if line.strip() else line) for line in block.strip("\n").splitlines()
        if not line.startswith("# Add this block")
    )
    return site[:end] + "\n\n" + BEGIN + "\n" + body + "\n" + END + site[end:]


def remove(site: str) -> str:
    if BEGIN not in site or END not in site:
        raise SystemExit("no marked /mesh/ location in the site file")
    a = site.index(BEGIN)
    b = site.index(END) + len(END)
    if not site[:a].endswith("\n\n"):
        raise SystemExit("the marked block was edited by hand; remove it by hand")
    return site[: a - 2] + site[b:]


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    mode, site_path = sys.argv[1], sys.argv[2]
    site = open(site_path, encoding="utf-8").read()
    if mode == "add":
        sys.stdout.write(add(site, open(sys.argv[3], encoding="utf-8").read()))
    elif mode == "remove":
        sys.stdout.write(remove(site))
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
