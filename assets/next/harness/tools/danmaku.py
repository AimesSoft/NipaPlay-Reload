"""Find external danmu-api episodes, or acquire one public Bilibili XML."""
import argparse
import re
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path
from public_http import request, get_json, public_url, cli, NOTICE


def api_url(base, path):
    public_url(base)
    p = urllib.parse.urlsplit(base)
    if p.query or p.fragment:
        raise ValueError("Service base must not contain query or fragment")
    return base.rstrip("/") + "/" + path.lstrip("/")


def xml_comments(body):
    text = body.decode("utf-8-sig")
    if re.search(r"<!DOCTYPE|<!ENTITY", text, re.I):
        raise ValueError("XML document declarations are not supported")
    root = ET.fromstring(text)
    if root.tag != "i":
        raise ValueError("Expected Bilibili XML, not a login page or JSON error")
    for entry in root.findall("d"):
        if len(entry.get("p", "").split(",")) < 4:
            raise ValueError("Invalid Bilibili XML comment attributes")
    return len(root.findall("d"))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    a = sub.add_parser("search", help="Search a user-supplied external danmu-api service")
    a.add_argument("keyword")
    a.add_argument("--base", required=True)
    a = sub.add_parser("episodes", help="List candidates without choosing or matching local files")
    a.add_argument("anime_id", type=int)
    a.add_argument("--base", required=True)
    a = sub.add_parser("fetch", help="Acquire one episode from the external service as XML")
    a.add_argument("episode_id", type=int)
    a.add_argument("--base", required=True)
    a.add_argument("--out", required=True)
    a = sub.add_parser("bilibili", help="Acquire public XML by cid, which is a video-part ID")
    a.add_argument("cid", type=int)
    a.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    if args.command == "search":
        url = api_url(args.base, "api/v2/search/anime") + "?" + urllib.parse.urlencode({"keyword": args.keyword})
    elif args.command == "episodes":
        url = api_url(args.base, f"api/v2/bangumi/{args.anime_id}")
    elif args.command == "fetch":
        url = api_url(args.base, f"api/v2/comment/{args.episode_id}") + "?format=xml"
    else:
        if args.cid <= 0:
            raise ValueError("cid must be positive")
        url = f"https://comment.bilibili.com/{args.cid}.xml"
    if args.command in {"search", "episodes"}:
        return {"source_url": url, "notice": NOTICE, "data": get_json(url)}
    body, final = request(url, timeout=60)
    count = xml_comments(body)
    output = Path(args.out).expanduser()
    # Exclusive creation: acquisition must not overwrite previous evidence.
    with output.open("xb") as stream:
        stream.write(body)
    return {"source_url": final, "notice": NOTICE, "path": str(output.resolve()),
            "format": "bilibili_xml", "comments": count, "bytes": len(body)}


if __name__ == "__main__":
    cli(main)
