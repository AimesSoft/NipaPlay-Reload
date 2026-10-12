"""Nyaa and AnimeTosho public RSS candidates; never enqueue downloads."""
import argparse
import re
import urllib.parse
import xml.etree.ElementTree as ET
from mikan import clean, hints
from public_http import request, cli, NOTICE

def _int(value):
    try:
        return int(str(value).replace(",", "").replace(" ", "").strip())
    except (TypeError, ValueError):
        return None


def _size(value):
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return int(value)
    text = str(value)
    m = re.search(r"([\d.]+)\s*(TiB|GiB|MiB|KiB|TB|GB|MB|KB|B)\b", text, re.I)
    if m:
        mult = {"b": 1, "kb": 1000, "kib": 1024, "mb": 10 ** 6, "mib": 1024 ** 2,
                "gb": 10 ** 9, "gib": 1024 ** 3, "tb": 10 ** 12, "tib": 1024 ** 4}
        return int(float(m[1]) * mult[m[2].lower()])
    m = re.match(r"^\s*(\d{4,})\s*$", text)
    return int(m[1]) if m else None


def magnet_for(info_hash, name=None):
    if not info_hash:
        return None
    value = "magnet:?xt=urn:btih:" + info_hash.lower()
    if name:
        value += "&dn=" + urllib.parse.quote(name)
    return value


def hash_from_magnet(magnet):
    m = re.search(r"xt=urn:btih:([0-9a-fA-F]{40}|[2-7A-Za-z]{32})", magnet or "")
    return m[1].lower() if m else None


def _local(element, name):
    for child in element.iter():
        if child.tag.split("}")[-1] == name:
            return child
    return None


def _local_text(element, name):
    child = _local(element, name)
    text = (child.text or "") if child is not None else ""
    return clean(text) if text.strip() else None


def _dedupe(items, key):
    seen, result = set(), []
    for item in items:
        value = key(item)
        if value and value not in seen:
            seen.add(value)
            result.append(item)
    return result


def _finish(result, limit):
    result["total_releases"] = len(result["releases"])
    if limit:
        result["releases"] = result["releases"][:limit]
    result["truncated"] = len(result["releases"]) < result["total_releases"]
    return result


def _release(title, **fields):
    item = {"title": clean(title), "hash": None, "magnet": None, "torrent_url": None,
            "detail_url": None, "size_text": None, "size_bytes": None, "seeders": None,
            "leechers": None, "published": None, "inferred": hints(clean(title))}
    item.update(fields)
    if not item.get("hash") and item.get("magnet"):
        item["hash"] = hash_from_magnet(item["magnet"])
    if item["hash"] and not item.get("magnet"):
        item["magnet"] = magnet_for(item["hash"])
    elif item["hash"] and item["magnet"] and "urn:btih:" not in item["magnet"].lower():
        # Some feeds give an external magnet with extra trackers; keep them, add the hash.
        item["magnet"] = item["magnet"] + "&xt=urn:btih:" + item["hash"]
    return item


def parse_nyaa_rss(text, url):
    reject_declarations(text)
    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        raise ValueError("Expected a Nyaa RSS feed, not a login or challenge page") from None
    if root.tag.split("}")[-1] != "rss":
        raise ValueError("Expected a Nyaa RSS feed")
    channel = root.find("channel")
    if channel is None:
        raise ValueError("Expected a Nyaa RSS channel")
    releases = []
    for item in channel.findall("item"):
        title = _local_text(item, "title")
        if not title:
            continue
        enclosure = _local(item, "enclosure")
        link = _local_text(item, "link")
        torrent_url = (enclosure.get("url") if enclosure is not None else None) \
            or (link if (link or "").endswith(".torrent") else None)
        info = _local_text(item, "infoHash")
        size_text = _local_text(item, "size")
        guid = _local_text(item, "guid")
        detail = guid if (guid or "").startswith("http") and "/view/" in guid else _local_text(item, "link")
        releases.append(_release(
            title, hash=(info or "").lower() or None, torrent_url=torrent_url,
            detail_url=detail, size_text=size_text, size_bytes=_size(size_text),
            seeders=_int(_local_text(item, "seeders")), leechers=_int(_local_text(item, "leechers")),
            published=_local_text(item, "pubDate"), category=_local_text(item, "category"), source="nyaa"))
    return {"source_url": url, "notice": NOTICE, "title": _local_text(channel, "title"),
            "releases": _dedupe(releases, lambda r: r["hash"] or r["title"])}


def parse_at_rss(text, url):
    reject_declarations(text)
    try:
        root = ET.fromstring(text)
    except ET.ParseError:
        raise ValueError("Expected an AnimeTosho RSS feed") from None
    channel = root.find("channel")
    if root.tag.split("}")[-1] != "rss" or channel is None:
        raise ValueError("Expected an AnimeTosho RSS feed")
    releases = []
    for item in channel.findall("item"):
        title = _local_text(item, "title")
        if not title:
            continue
        enclosure = _local(item, "enclosure")
        torrent_url = enclosure.get("url") if enclosure is not None else None
        info = None
        m = re.search(r"/torrent/([0-9a-fA-F]{40})/", torrent_url or "")
        if m:
            info = m[1].lower()
        description = re.sub(r"<[^>]+>", " ", _local_text(item, "description") or "")
        size_text = None
        s = re.search(r"Total Size\s*:?\s*([\d.]+\s*[KMGT]i?B)", description, re.I)
        if s:
            size_text = s[1]
        releases.append(_release(
            title, hash=info, torrent_url=torrent_url, detail_url=_local_text(item, "link"),
            size_text=size_text, size_bytes=_size(size_text), published=_local_text(item, "pubDate"),
            source="animetosho"))
    return {"source_url": url, "notice": NOTICE, "title": _local_text(channel, "title"),
            "releases": _dedupe(releases, lambda r: r["hash"] or r["title"])}


def reject_declarations(text):
    if re.search(r"<!DOCTYPE|<!ENTITY", text, re.I):
        raise ValueError("RSS document declarations are not supported")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("site", choices=["nyaa", "animetosho"])
    parser.add_argument("query", nargs="?", default="")
    parser.add_argument("--rss", help="Read a feed on this provider instead of searching")
    parser.add_argument("--limit", type=int, default=20, help="0 returns all items in this response")
    parser.add_argument("--category", help="Nyaa category, e.g. 1_2")
    args = parser.parse_args(argv)
    if args.limit < 0:
        raise ValueError("Limit must be nonnegative")
    if args.site == "nyaa":
        hosts = {"nyaa.si", "www.nyaa.si"}
        params = {"page": "rss", "q": args.query}
        if args.category:
            params["c"] = args.category
        url = args.rss or "https://nyaa.si/?" + urllib.parse.urlencode(params)
        parse = parse_nyaa_rss
    else:
        hosts = {"feed.animetosho.org", "animetosho.org"}
        url = args.rss or "https://feed.animetosho.org/rss2?" + urllib.parse.urlencode({"only_tor": "1", "q": args.query})
        parse = parse_at_rss
    body, final = request(url, hosts=hosts)
    return _finish(parse(body.decode("utf-8-sig"), final), args.limit)


if __name__ == "__main__":
    cli(main)
