#!/usr/bin/env python3
"""Drive the lab-only VM service extension, never a NipaPlay Agent action."""
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path


class LabVM:
    def __init__(self, log):
        text = Path(log).read_text(errors="replace")
        match = re.search(r"Dart VM service is listening on (http://[^\s]+)", text)
        if not match:
            raise RuntimeError("VM service not in lab log")
        self.url = match[1]
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        vm = self.rpc("getVM")
        self.isolate = next(i["id"] for i in vm["isolates"] if i["name"] == "main")

    def rpc(self, method, **params):
        request = self.url + method + "?" + urllib.parse.urlencode(params)
        with self.opener.open(request, timeout=30) as response:
            data = json.load(response)
        if "error" in data:
            raise RuntimeError(json.dumps(data["error"], ensure_ascii=False))
        return data["result"]

    def chat(self, op, **params):
        return self.rpc("ext.nipaplay.chat", isolateId=self.isolate, op=op, **params)


if __name__ == "__main__":
    vm = LabVM(sys.argv[1])
    params = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
    print(json.dumps(vm.chat(sys.argv[2], **params), ensure_ascii=False))
