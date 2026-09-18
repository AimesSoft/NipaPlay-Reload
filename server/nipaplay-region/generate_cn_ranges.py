#!/usr/bin/env python3
"""从 APNIC 委派文件生成 cn_ranges.json。

用法：
    python3 generate_cn_ranges.py [delegated-apnic-latest] [输出路径]

国内备用服务器的 /region 接口用这份数据判断调用方 IP 是否属于中国大陆。
数据只包含委派给 CN 的地址块，合并相邻/包含区间后写成紧凑 JSON，
运行期不需要联网，也不需要 GeoIP 数据库。
"""

import ipaddress
import json
import os
import sys
import urllib.request

APNIC_URL = "https://ftp.apnic.net/stats/apnic/delegated-apnic-latest"
DEFAULT_OUTPUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cn_ranges.json")


def merge(ranges):
    ranges.sort()
    merged = []
    for start, end in ranges:
        if merged and start <= merged[-1][1] + 1:
            if end > merged[-1][1]:
                merged[-1][1] = end
        else:
            merged.append([start, end])
    return merged


def collect(lines):
    v4, v6 = [], []
    for line in lines:
        parts = line.strip().split("|")
        if len(parts) < 7 or parts[0] != "apnic" or parts[1] != "CN":
            continue
        if parts[2] == "ipv4":
            start = int(ipaddress.IPv4Address(parts[3]))
            v4.append((start, start + int(parts[4]) - 1))
        elif parts[2] == "ipv6":
            net = ipaddress.IPv6Network(f"{parts[3]}/{parts[4]}", strict=False)
            v6.append((int(net.network_address), int(net.broadcast_address)))
    return merge(v4), merge(v6)


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else None
    output = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUTPUT

    if source:
        with open(source, "r", encoding="utf-8") as handle:
            lines = handle.readlines()
    else:
        with urllib.request.urlopen(APNIC_URL, timeout=120) as response:
            lines = response.read().decode("utf-8", "replace").splitlines()

    v4, v6 = collect(lines)
    with open(output, "w", encoding="utf-8") as handle:
        json.dump({"v4": v4, "v6": v6}, handle, separators=(",", ":"))
    print(f"wrote {output}: v4={len(v4)} v6={len(v6)} ranges")


if __name__ == "__main__":
    main()
