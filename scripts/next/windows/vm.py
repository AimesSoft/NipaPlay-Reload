#!/usr/bin/env python
"""Call a service extension of the lab instance: vm.py <run.log> <ext.name> [k=v ...]
A value written @path is read from that file (keeps a key off the command line).
The reply is printed as JSON; --delete-files removes the @path files afterwards."""
import json, re, sys, urllib.parse, urllib.request
from pathlib import Path
args = sys.argv[1:]
delete = '--delete-files' in args
args = [a for a in args if a != '--delete-files']
log, ext, *rest = args
text = Path(log).read_text(errors="replace")
url = re.findall(r"Dart VM service is listening on (http://[^\s]+)", text)[-1]
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
def rpc(method, **params):
    with opener.open(url + method + "?" + urllib.parse.urlencode(params), timeout=600) as r:
        data = json.load(r)
    if "error" in data:
        raise SystemExit(json.dumps(data["error"], ensure_ascii=False))
    return data["result"]
iso = next(i["id"] for i in rpc("getVM")["isolates"] if i["name"] == "main")
params, files = {}, []
for kv in rest:
    k, v = kv.split("=", 1)
    if v.startswith("@"):
        files.append(v[1:]); v = Path(v[1:]).read_text(encoding="utf-8")
    params[k] = v
try:
    res = rpc(ext, isolateId=iso, **params)
finally:
    if delete:
        for f in files: Path(f).unlink(missing_ok=True)
print(json.dumps(res, ensure_ascii=False, indent=1))
