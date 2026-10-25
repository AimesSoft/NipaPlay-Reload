#!/usr/bin/env python3
"""Drive ext.nipaplay.nextui of a lab instance: nx.py <log> <op> [k=v ...]"""
import json, re, sys, urllib.parse, urllib.request
from pathlib import Path
log, op, *rest = sys.argv[1:]
text = Path(log).read_text(errors="replace")
url = re.findall(r"Dart VM service is listening on (http://[^\s]+)", text)[-1]
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
def rpc(method, **params):
    with opener.open(url + method + "?" + urllib.parse.urlencode(params), timeout=60) as r:
        data = json.load(r)
    if "error" in data:
        raise SystemExit(json.dumps(data["error"], ensure_ascii=False))
    return data["result"]
iso = next(i["id"] for i in rpc("getVM")["isolates"] if i["name"] == "main")
params = dict(kv.split("=", 1) for kv in rest)
res = rpc("ext.nipaplay.nextui", isolateId=iso, op=op, **params)
print(json.dumps(res, ensure_ascii=False, indent=1))
