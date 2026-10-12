"""Fetch a public API response, preserving its source URL. No configured hosts."""
import argparse
import json
import urllib.parse
from pathlib import Path
from public_http import request, cli, NOTICE


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", help="Public HTTPS URL")
    parser.add_argument("--params", default="{}", help="JSON object of GET query fields")
    parser.add_argument("--json-file", help="JSON request body for POST-based queries")
    args = parser.parse_args(argv)
    params = json.loads(args.params)
    if not isinstance(params, dict):
        raise ValueError("Parameters must be a JSON object")
    p = urllib.parse.urlsplit(args.url)
    query = p.query + ("&" if p.query and params else "") + urllib.parse.urlencode(params, doseq=True)
    url = urllib.parse.urlunsplit(p._replace(query=query))
    payload = None
    if args.json_file:
        payload = json.dumps(json.loads(Path(args.json_file).read_text(encoding="utf-8"))).encode()
    body, final = request(url, payload=payload)
    return {"source_url": final, "notice": NOTICE, "data": json.loads(body.decode("utf-8-sig"))}


if __name__ == "__main__":
    cli(main)
