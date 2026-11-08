#!/usr/bin/env python3
"""Editable agent-owned subscription policy. Host code only stores its results."""
import argparse
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
import urllib.parse
import uuid
from datetime import datetime, timezone

import rss
import torznab
import mikan
from subscription_io import ROOT, call, secret, without_secret, emit


def now():
    return datetime.now(timezone.utc).isoformat()


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


class Records:
    def __init__(self, root):
        self.root = Path(root) / "subscriptions"
        self.root.mkdir(parents=True, exist_ok=True)

    @contextmanager
    def locked(self):
        # One shared file lock also prevents a fast completion hook overtaking
        # download.add's return and the job mapping write. Never lock during a
        # feed fetch. OS locks are released after crashes.
        with (self.root / "lock").open("a+b") as stream:
            if os.name == "nt":
                import msvcrt
                stream.write(b"0"); stream.flush(); stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_LOCK, 1)
            else:
                import fcntl
                fcntl.flock(stream, fcntl.LOCK_EX)
            try:
                yield
            finally:
                if os.name == "nt":
                    stream.seek(0); msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    fcntl.flock(stream, fcntl.LOCK_UN)

    def read(self, name):
        file = self.root / (digest(name) + ".json")
        return json.loads(file.read_text(encoding="utf-8")) if file.exists() else {}

    def write(self, name, data):
        file = self.root / (digest(name) + ".json")
        pending = file.with_suffix(".pending")
        pending.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
        pending.replace(file)


def candidates(source):
    kind = source["kind"]
    if kind == "rss":
        url = source["url"]
        if source.get("credentialName"):
            parsed = urllib.parse.urlsplit(url)
            parameter = source["credentialParameter"]
            fields = urllib.parse.parse_qsl(parsed.query) + [(parameter, "{secret}")]
            url = urllib.parse.urlunsplit(parsed._replace(query=urllib.parse.urlencode(fields, safe="{}")))
        entries = rss.read(url, source.get("credentialName"))["entries"]
    elif kind == "torznab":
        entries = torznab.query(source["url"], source.get("operation", "search"),
                                source.get("credentialName"), **source.get("params", {}))["entries"]
    elif kind == "mikan":
        entries = mikan.main(["rss", source["url"], "--limit", "0"])["releases"]
    else:
        raise ValueError("Unknown source kind")
    result = []
    for entry in entries:
        url = entry.get("magnet") or entry.get("download_url") or entry.get("enclosure") or entry.get("torrent_url")
        if not url:
            continue
        if not url.startswith(("https://", "http://", "magnet:?")):
            continue
        result.append({"title": entry["title"], "url": url,
                       "size": entry.get("size", entry.get("size_bytes_reported")),
                       "credentialName": source.get("credentialName")})
    return result


def select(entries, rules, kind, handled_episodes=()):
    # Nothing is subscribed by default: the agent must write an explicit rule.
    if not rules.get("include"):
        raise ValueError("Write explicit include expressions before subscribing")
    allowed = {"include", "exclude", "episodeRegex", "minBytes", "maxBytes", "priority", "ask", "errorWakeAfter"}
    if set(rules) - allowed:
        raise ValueError("Unknown rule field")
    include = [re.compile(p) for p in rules["include"]]
    exclude = [re.compile(p) for p in rules.get("exclude", [])]
    priority = [re.compile(p) for p in rules.get("priority", [])]
    episode_re = re.compile(rules["episodeRegex"]) if rules.get("episodeRegex") else None
    if kind == "series" and (episode_re is None or "episode" not in episode_re.groupindex):
        raise ValueError("Series require episodeRegex with a named episode group")
    groups = {}
    for entry in entries:
        title, size = entry["title"], entry["size"]
        if not all(p.search(title) for p in include) or any(p.search(title) for p in exclude):
            continue
        if any(k in rules and (size is None or (size < rules[k] if k == "minBytes" else size > rules[k]))
               for k in ("minBytes", "maxBytes")):
            continue
        match = episode_re.search(title) if episode_re else None
        if episode_re is not None and match is None:
            continue
        episode = match.group("episode") if match else "movie"
        if episode in handled_episodes:
            continue
        rank = next((i for i, p in enumerate(priority) if p.search(title)), len(priority))
        item = {**entry, "episode": episode, "rank": rank,
                "key": digest((entry.get("credentialName") or "") + "\n" + entry["url"])}
        groups.setdefault(episode, {})[item["key"]] = item
    picked, conflicts = [], []
    for episode, options in groups.items():
        best = min(e["rank"] for e in options.values())
        bests = [e for e in options.values() if e["rank"] == best]
        if len(bests) > 1:
            conflicts.append(episode)
        else:
            picked.append(bests[0])
    return picked, conflicts


def inspect(subscription, loader=candidates, handled_episodes=()):
    facts = subscription["facts"]
    entries = [e for source in facts["sources"] for e in loader(source)]
    return select(entries, facts["rules"], subscription["kind"], handled_episodes)


def wake(host, subscription, reason):
    host("agent.wake", {"instruction": "请核对订阅《" + subscription["title"] + "》：" + reason,
                         "facts": {"subscriptionId": subscription["id"], "reason": reason}})


def run_one(subscription, records, host=call, loader=candidates, preview=False):
    ident, facts = subscription["id"], subscription["facts"]
    report = {"id": ident, "reportId": str(uuid.uuid4()), "checkedAt": now(),
              "found": [], "downloads": [], "errors": []}
    try:
        handled = ()
        if not preview:
            with records.locked():
                saved = records.read("subscription:" + ident)
                handled = set(saved.get("episodes", {}))
                pending = [e for e in saved.get("processed", {}).values()
                           if e.get("status") == "intent" and not e.get("notified")]
            if pending:
                wake(host, subscription, "下载请求结果不明，请核对任务后处理 records 中的 intent")
                with records.locked():
                    saved = records.read("subscription:" + ident)
                    for entry in saved.get("processed", {}).values():
                        if entry.get("status") == "intent":
                            entry["notified"] = True
                    records.write("subscription:" + ident, saved)
        picked, conflicts = inspect(subscription, loader, handled)
        if len(picked) > 100:
            raise ValueError("Split this subscription into smaller explicit checks")
        report["found"] = [{"title": e["title"][:500], "key": e["key"], "episode": e["episode"]} for e in picked]
        if preview:
            return {**report, "conflicts": conflicts, "preview": True}
        if conflicts or facts["rules"].get("ask"):
            wake(host, subscription, "候选冲突" if conflicts else "规则要求询问")
            host("subscription.report", report)
            return report
        for entry in picked:
            with records.locked():
                # Pause/remove may have happened while fetching the feed.
                current = host("subscription.get", {"id": ident})
                if current["state"] != "active" or current.get("revision") != subscription.get("revision"):
                    break
                saved = records.read("subscription:" + ident)
                processed = saved.setdefault("processed", {})
                episodes = saved.setdefault("episodes", {})
                previous = processed.get(entry["key"], {})
                if previous.get("status") == "intent" and not previous.get("notified"):
                    wake(host, subscription, "下载请求结果不明，请核对任务后处理 records 中的 intent")
                    previous["notified"] = True
                    records.write("subscription:" + ident, saved)
                if entry["key"] in processed or entry["episode"] in episodes:
                    continue
                # A persisted intent survives unknown transport outcomes. Do
                # not issue another download until the agent reconciles it.
                processed[entry["key"]] = {"status": "intent", "episode": entry["episode"]}
                episodes[entry["episode"]] = entry["key"]
                records.write("subscription:" + ident, saved)
                url = entry["url"]
                if "{secret}" in url:
                    if not entry.get("credentialName"):
                        raise ValueError("Candidate needs a named secret")
                    url = url.replace("{secret}", urllib.parse.quote(secret(entry["credentialName"]), safe=""))
                # Options are the agent's own declaration, not publisher data.
                result = host("download.add", {**facts.get("download", {}), "source": url})
                job = result["job"]
                job_id = job["jobId"]
                old_job = records.read("job:" + job_id)
                if old_job and old_job.get("subscriptionId") != ident:
                    raise ValueError("Existing job belongs to another subscription")
                binding = facts.get("bindings", {}).get(entry["episode"])
                record = {"subscriptionId": ident, "workId": subscription.get("workId"),
                          "episode": entry["episode"], "title": entry["title"][:500],
                          "binding": binding, "jobId": job_id, "completed": old_job.get("completed", [])}
                records.write("job:" + job_id, record)
                processed[entry["key"]] = {"status": "queued", "jobId": job_id, "episode": entry["episode"]}
                records.write("subscription:" + ident, saved)
                report["downloads"].append({"jobId": job_id, "title": entry["title"][:500], "episode": entry["episode"]})
        with records.locked():
            saved = records.read("subscription:" + ident)
            saved["consecutiveErrors"] = 0
            records.write("subscription:" + ident, saved)
    except Exception as error:
        if preview:
            raise
        report["errors"].append(type(error).__name__ + ": 检查失败，请核对来源、规则或待核对下载记录")
        with records.locked():
            saved = records.read("subscription:" + ident)
            count = saved["consecutiveErrors"] = saved.get("consecutiveErrors", 0) + 1
            records.write("subscription:" + ident, saved)
        threshold = facts.get("rules", {}).get("errorWakeAfter", 3)
        if not isinstance(threshold, int) or threshold < 1:
            threshold = 3
        if count == threshold:
            wake(host, subscription, "连续检查出错；请核对 records 中待核对的请求")
    host("subscription.report", report)
    return report


def complete(event, records, host=call):
    data = event["data"]
    job_id, file = data["jobId"], data["file"]
    with records.locked():
        record = records.read("job:" + job_id)
        if not record or event["objectId"] in record.get("completed", []):
            return {"handled": False}
        # A remote qBittorrent's file has no local file entity to bind here.
        file_id = (file.get("media") or {}).get("fileId")
        binding = record.get("binding")
        if file.get("local") is False or file.get("verification") != "verified" or not file_id or not binding:
            wake(host, {"id": record["subscriptionId"], "title": record["title"]}, "完成文件需要确认身份或传输；模板没有足够的明确绑定资料")
            return {"handled": False, "needsDecision": True}
        # A torrent with multiple videos needs an explicit file-index map. No
        # filename matching or applying one episode to every file of a pack.
        chosen = binding.get("files", {}).get(str(file["index"]))
        if chosen is None:
            wake(host, {"id": record["subscriptionId"], "title": record["title"]}, "请提供该文件索引的明确绑定")
            return {"handled": False, "needsDecision": True}
        entry = {**chosen, "kind": "file", "entityId": file_id}
        entry.pop("path", None)
        result = host("media.identity.bind_batch", {"requestId": "subscription-" + digest(event["objectId"]), "entries": [entry]})
        # Report domain failure, never label an accepted invocation as binding
        # success without checking the per-entry contract.
        if len(result.get("entries", [])) != 1 or any(e.get("error") for e in result["entries"]):
            raise RuntimeError("Identity binding failed")
    host("activity.report", {"title": "订阅文件已绑定", "source": "subscription completion hook",
                             "facts": {"subscriptionId": record["subscriptionId"], "jobId": job_id, "fileId": file_id, "episode": record["episode"]}})
    # Read the existing organization policy. Moving files belongs to the
    # agent's existing organization workflow, never a second naming engine.
    settings = host("settings.get", {"keys": ["library.fileOrganization", "library.fileOrganizationRules"]})
    values = {e["key"]: e["value"] for e in settings.get("results", []) if "value" in e}
    policy = values.get("library.fileOrganization")
    if policy not in {"off", "ask", "auto"}:
        raise ValueError("Unknown library organization policy")
    if policy != "off":
        host("agent.wake", {"instruction": "订阅文件已按预先确认身份绑定。请沿用现有 library.fileOrganization 和 library.fileOrganizationRules 整理：ask 用 ui.ask 等用户回答；auto 按已保存授权和规则归档。不得破坏做种、覆盖、移出授权根目录或丢失字幕弹幕、身份和进度关联；无法保留关联时报告并保持文件原样。不要建立另一套命名规则。",
                            "facts": {"subscriptionId": record["subscriptionId"], "jobId": job_id,
                                      "fileId": file_id, "organization": values}})
    host("subscription.report", {"id": record["subscriptionId"], "reportId": "completed-" + digest(event["objectId"]),
                                  "checkedAt": event["occurredAt"], "found": [], "downloads": [], "errors": []})
    with records.locked():
        record = records.read("job:" + job_id)
        record.setdefault("completed", []).append(event["objectId"])
        records.write("job:" + job_id, record)
    return {"handled": True, "fileId": file_id}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", help="Preview a subscription JSON file without any write or download")
    parser.add_argument("--complete", action="store_true", help="Read download.file_completed event JSON from stdin")
    args = parser.parse_args(argv)
    if args.preview:
        return run_one(json.loads(Path(args.preview).read_text(encoding="utf-8")), None, preview=True)
    records = Records(ROOT / "records")
    if args.complete:
        return complete(json.load(sys.stdin), records)
    subscriptions = call("subscription.list", {"state": "active", "limit": 500})["subscriptions"]
    program = Path(__file__).resolve().relative_to(ROOT).as_posix()
    return {"reports": [run_one(s, records) for s in subscriptions if s["program"] == program]}


if __name__ == "__main__":
    emit(main)
