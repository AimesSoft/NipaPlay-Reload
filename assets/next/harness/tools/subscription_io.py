"""In-memory host calls and private-feed transport. Never log credentials."""
import json
import re
from pathlib import Path
import subprocess
import sys
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MAX_BYTES = 16 * 1024 * 1024


def call(action, inputs):
    result = subprocess.run([sys.executable, str(ROOT / "nipa"), "--output-full",
                             "call", action, "-"], input=json.dumps(inputs),
                            capture_output=True, text=True, encoding="utf-8", timeout=120)
    try:
        envelope = json.loads(result.stdout)
    except ValueError:
        raise RuntimeError("Host returned invalid JSON") from None
    if result.returncode or envelope.get("status") != "completed":
        raise RuntimeError("Host call failed: " + action) from None
    return envelope["result"]


def secret(name):
    return call("secrets.get", {"name": name})["value"]


def origin(url):
    p = urllib.parse.urlsplit(url)
    if p.scheme not in {"https", "http"} or not p.hostname or p.username or p.password:
        raise ValueError("Use an explicit HTTP(S) endpoint without userinfo")
    return p.scheme, p.hostname, p.port or (443 if p.scheme == "https" else 80)


class SameOrigin(urllib.request.HTTPRedirectHandler):
    def __init__(self, selected):
        self.selected = selected

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if origin(newurl) != self.selected:
            raise ValueError("Cross-origin redirect refused")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url):
    selected = origin(url)
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "NipaPlay-Harness/1.0",
                                                       "Accept-Encoding": "identity"})
        with urllib.request.build_opener(SameOrigin(selected)).open(request, timeout=30) as response:
            body = response.read(MAX_BYTES + 1)
    except Exception:
        # urllib exceptions and server bodies can embed the authenticated URL.
        raise RuntimeError("Feed request failed") from None
    if len(body) > MAX_BYTES:
        raise ValueError("Feed exceeds 16 MiB")
    return body


def xml(body):
    if b"<!DOCTYPE" in body.upper() or b"<!ENTITY" in body.upper():
        raise ValueError("XML declarations with entities are not accepted")
    try:
        return ET.fromstring(body)
    except ET.ParseError:
        raise ValueError("Invalid feed XML") from None


def local(tag):
    return tag.rsplit("}", 1)[-1]


def text(node, name):
    child = next((n for n in node if local(n.tag) == name), None)
    return "" if child is None else "".join(child.itertext()).strip()


def without_secret(value, private):
    """Keep reusable URL templates, never authenticated URLs in evidence."""
    if isinstance(value, dict):
        return {k: without_secret(v, private) for k, v in value.items()}
    if isinstance(value, list):
        return [without_secret(v, private) for v in value]
    if isinstance(value, str) and private:
        for form in {private, urllib.parse.quote(private, safe=""), urllib.parse.quote_plus(private)}:
            value = value.replace(form, "{secret}")
    if isinstance(value, str):
        def safe_url(match):
            url = match[0]
            p = urllib.parse.urlsplit(url)
            if p.username or p.password or any(
                    re.search(r"pass|auth|token|secret|cookie|key|signature", key, re.I) and item != "{secret}"
                    for key, item in urllib.parse.parse_qsl(p.query)):
                return "[redacted-url]"
            return url
        value = re.sub(r"https?://[^\s<>\"']+", safe_url, value)
    return value


def emit(main):
    try:
        print(json.dumps(main(), ensure_ascii=False, indent=2))
    except Exception as error:
        # Controlled type only: no site body, URL, subprocess output or key.
        print(json.dumps({"error": type(error).__name__, "message": "Query failed; check endpoint, secret name and feed format"}), file=sys.stderr)
        raise SystemExit(1)
