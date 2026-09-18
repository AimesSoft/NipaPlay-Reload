#!/usr/bin/env python3
"""NipaPlay 归属地服务。

国内备用服务器用它判断调用方 IP 是否属于中国大陆，客户端据此在
主（香港域名）/ 备（国内 IP）网关之间自动选择。

IP 段数据来自 APNIC 委派文件（apnic|CN|ipv4 / ipv6），已合并为有序区间。
只监听回环地址，真实客户端 IP 由 nginx 通过 X-Real-IP 注入。
"""

import bisect
import ipaddress
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
DATA_FILE = os.path.join(HERE, "cn_ranges.json")
LISTEN_HOST = os.environ.get("REGION_LISTEN_HOST", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("REGION_LISTEN_PORT", "18100"))

with open(DATA_FILE, "r", encoding="utf-8") as handle:
    _data = json.load(handle)

V4_RANGES = _data["v4"]
V6_RANGES = _data["v6"]
V4_STARTS = [item[0] for item in V4_RANGES]
V6_STARTS = [item[0] for item in V6_RANGES]


def _in_ranges(ranges, starts, value):
    index = bisect.bisect_right(starts, value) - 1
    return index >= 0 and ranges[index][0] <= value <= ranges[index][1]


def classify(ip_text):
    """返回 'CN' / 'OVERSEAS'；无法解析时返回 None。"""
    text = (ip_text or "").strip()
    if not text:
        return None
    # nginx 传过来的可能是 IPv6 映射形式 ::ffff:1.2.3.4
    if text.lower().startswith("::ffff:"):
        text = text[7:]
    try:
        address = ipaddress.ip_address(text)
    except ValueError:
        return None
    if address.version == 4:
        return "CN" if _in_ranges(V4_RANGES, V4_STARTS, int(address)) else "OVERSEAS"
    return "CN" if _in_ranges(V6_RANGES, V6_STARTS, int(address)) else "OVERSEAS"


def client_ip(handler):
    real_ip = handler.headers.get("X-Real-IP")
    if real_ip:
        return real_ip.strip()
    forwarded = handler.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return handler.client_address[0]


class RegionHandler(BaseHTTPRequestHandler):
    server_version = "nipaplay-region/1.0"
    protocol_version = "HTTP/1.1"

    def _send_json(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802 - BaseHTTPRequestHandler API
        path = self.path.split("?", 1)[0].rstrip("/") or "/"
        if path == "/healthz":
            self._send_json(200, {"ok": True, "service": "nipaplay-region"})
            return
        if path != "/region":
            self._send_json(404, {"error": "not found"})
            return
        ip = client_ip(self)
        region = classify(ip)
        if region is None:
            # 解析不出归属地时让客户端回退到可达性判定。
            self._send_json(400, {"error": "unresolvable client ip", "ip": ip})
            return
        self._send_json(
            200,
            {
                "ip": ip,
                "region": region,
                "country": region,
                "source": "apnic-delegated",
            },
        )

    def do_HEAD(self):  # noqa: N802
        self.do_GET()

    def do_OPTIONS(self):  # noqa: N802
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write(
            "%s - %s\n" % (self.address_string(), fmt % args)
        )


def main():
    server = ThreadingHTTPServer((LISTEN_HOST, LISTEN_PORT), RegionHandler)
    sys.stderr.write(
        "nipaplay-region listening on %s:%d (v4=%d v6=%d ranges)\n"
        % (LISTEN_HOST, LISTEN_PORT, len(V4_RANGES), len(V6_RANGES))
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
