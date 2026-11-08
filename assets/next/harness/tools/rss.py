"""RSS/Atom evidence only. Inject a vault secret into an explicit {secret} URL."""
import argparse
import re
import urllib.parse
from subscription_io import fetch, secret, xml, local, text, without_secret, emit


def parse(body):
    root = xml(body)
    if local(root.tag) not in {"rss", "feed", "RDF"}:
        raise ValueError("Expected RSS or Atom, not a login page")
    result = []
    for item in root.iter():
        if local(item.tag) not in {"item", "entry"}:
            continue
        links = [n for n in item if local(n.tag) == "link"]
        link = next((n.get("href") or (n.text or "").strip() for n in links
                     if n.get("rel", "alternate") == "alternate"), "")
        enclosure = next((n for n in item if local(n.tag) == "enclosure" or
                          local(n.tag) == "link" and n.get("rel") == "enclosure"), None)
        size = enclosure.get("length") if enclosure is not None else None
        result.append({"title": text(item, "title"), "link": link,
                       "enclosure": enclosure.get("url") or enclosure.get("href") if enclosure is not None else None,
                       "size": int(size) if size and size.isdecimal() else None,
                       "published_at": text(item, "pubDate") or text(item, "published") or text(item, "updated") or None})
    return result


def read(url, secret_name=None):
    if any(re.search(r"pass|auth|token|secret|cookie|key", key, re.I) and value != "{secret}"
           for key, value in urllib.parse.parse_qsl(urllib.parse.urlsplit(url).query)):
        raise ValueError("RSS credentials must come from a named secret")
    private = secret(secret_name) if secret_name else None
    if "{secret}" in url and private is None:
        raise ValueError("URL template requires --secret")
    if private is not None and "{secret}" not in url:
        raise ValueError("Use {secret} in the RSS URL")
    actual = url.replace("{secret}", urllib.parse.quote(private, safe="")) if private else url
    return {"notice": "Publisher evidence; no version choice or subscription.",
            "secretRef": secret_name,
            "entries": without_secret(parse(fetch(actual)), private)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url")
    parser.add_argument("--secret")
    args = parser.parse_args(argv)
    return read(args.url, args.secret)


if __name__ == "__main__":
    emit(main)
