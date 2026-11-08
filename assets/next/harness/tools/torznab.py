"""Torznab evidence for an explicit Jackett/Prowlarr API endpoint."""
import argparse
import urllib.parse
from subscription_io import fetch, secret, xml, local, text, without_secret, emit


def parse(body, indexer=None):
    root = xml(body)
    if local(root.tag) == "error":
        raise ValueError("Indexer reported an error")
    entries = []
    for item in root.iter("item"):
        attrs = {n.get("name"): n.get("value") for n in item if local(n.tag) == "attr"}
        enclosure = item.find("enclosure")
        size = attrs.get("size") or (enclosure.get("length") if enclosure is not None else None)
        seeders = attrs.get("seeders")
        entries.append({"title": text(item, "title"), "size": int(size) if size and size.isdecimal() else None,
                        "seeders": int(seeders) if seeders and seeders.isdecimal() else None,
                        "download_url": enclosure.get("url") if enclosure is not None else text(item, "link"),
                        "magnet": attrs.get("magneturl"), "published_at": text(item, "pubDate") or None,
                        "indexer": text(item, "jackettindexer") or text(item, "prowlarrindexer") or indexer})
    return entries


def query(url, operation="search", secret_name=None, **params):
    if operation not in {"caps", "search", "rss"}:
        raise ValueError("Unknown Torznab operation")
    if set(params) - {"q", "cat", "tmdbid", "imdbid", "season", "ep", "indexer"}:
        raise ValueError("Unknown search parameter")
    private = secret(secret_name) if secret_name else None
    p = urllib.parse.urlsplit(url)
    existing = urllib.parse.parse_qsl(p.query)
    if any(k.lower() == "apikey" for k, _ in existing):
        raise ValueError("API key must come from --secret")
    fields = existing + [("t", "caps" if operation == "caps" else "search")]
    fields += [(k, v) for k, v in params.items() if v is not None and k != "indexer"]
    if private is not None:
        fields.append(("apikey", private))
    body = fetch(urllib.parse.urlunsplit(p._replace(query=urllib.parse.urlencode(fields))))
    if operation == "caps":
        root = xml(body)
        if local(root.tag) != "caps":
            raise ValueError("Expected Torznab caps")
        data = {"categories": [{"id": n.get("id"), "name": n.get("name")} for n in root.iter() if local(n.tag) in {"category", "subcat"}],
                "searching": [{"type": local(n.tag), **n.attrib} for n in root.iter() if local(n.tag).endswith("-search")]}
    else:
        data = {"entries": parse(body, params.get("indexer"))}
    return without_secret({"notice": "Indexer observations; peer counts are not availability guarantees.", "secretRef": secret_name, **data}, private)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["caps", "search", "rss"])
    parser.add_argument("--url", required=True, help="Exact API endpoint, including the selected indexer path")
    parser.add_argument("--secret", help="Vault name; API key is read only with nipa call secrets.get")
    for name in ["q", "cat", "tmdbid", "imdbid", "season", "ep", "indexer"]:
        parser.add_argument("--" + name)
    args = vars(parser.parse_args(argv))
    return query(args.pop("url"), args.pop("operation"), args.pop("secret"), **args)


if __name__ == "__main__":
    emit(main)
