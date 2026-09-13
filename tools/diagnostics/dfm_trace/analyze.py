"""Analyze DFM JSONL traces without assuming Dart/native clocks share an epoch."""
import argparse
import collections
import json
from pathlib import Path


def stats(values):
    values = sorted(values)
    if not values:
        return {"count": 0}
    return {"count": len(values), **{
        label: round(values[round((len(values) - 1) * fraction)] / 1000, 3)
        for label, fraction in [("p50_ms", .5), ("p95_ms", .95), ("p99_ms", .99), ("max_ms", 1)]
    }}


def analyze(records):
    native, dart, loss = [], [], collections.Counter()
    for record in records:
        event = record.get("event")
        if event == "dart_batch":
            data = record["data"]
            loss["dart_events"] += data.get("dropped", 0)
            dart.extend(data.get("events", []))
        elif event == "native_dropped":
            loss["native_records"] += record["count"]
        elif event == "size_limit":
            loss["size_limit"] += 1
        else:
            native.append(record)
    loss["failed_dart_batches"] = sum(e.get("event") == "dart_batch_failed" for e in dart)
    stages = {}
    long_frames = []
    definitions = [
        (native, "native_queue", "enqueue", "process_begin"),
        (native, "native_prepare", "process_begin", "process_end"),
        (native, "platform_ffi_wait", "ffi_enter", "ffi_return"),
        (native, "draw_cpu_and_submit", "draw_begin", "draw_submitted"),
        (native, "gpu_completion_latency", "draw_submitted", "gpu_complete"),
        (dart, "payload_prepare", "payload_begin", "encode_begin"),
        (dart, "json_encode", "encode_begin", "send_begin"),
        (dart, "dart_channel_roundtrip", "send_begin", "send_return"),
        (dart, "snapshot_to_send", "snapshot", "send_begin"),
    ]
    for events, name, begin, end in definitions:
        starts, finishes = {}, {}
        for event in events:
            key = (event.get("engine"), event.get("frame", 0))
            if not key[1]:
                continue
            if event["event"] == begin:
                starts[key] = event["t_us"]
            elif event["event"] == end:
                finishes[key] = event["t_us"]
        durations = []
        for key in starts.keys() & finishes.keys():
            duration = finishes[key] - starts[key]
            if duration >= 0:
                durations.append(duration)
                long_frames.append({"stage": name, "engine": key[0], "frame": key[1],
                                    "duration_ms": round(duration / 1000, 3)})
        stages[name] = stats(durations)

    gaps = {}
    for events, name, timestamp in [
        (dart, "tick", "t_us"), (dart, "snapshot", "t_us"),
        (dart, "flutter_frame", "raster_end_us"),
        (native, "gpu_complete", "t_us"), (native, "texture_sample", "t_us"),
    ]:
        by_engine = collections.defaultdict(list)
        for event in events:
            if event["event"] == name:
                by_engine[event.get("engine", 0)].append(event[timestamp])
        durations = []
        for times in by_engine.values():
            times.sort()
            durations.extend(b - a for a, b in zip(times, times[1:]) if b > a)
        gaps[name] = stats(durations)

    native_frames = collections.defaultdict(set)
    for event in native:
        if event.get("frame", 0):
            native_frames[event["event"]].add((event.get("engine"), event["frame"]))
    prepared = native_frames["process_end"]
    drawn = native_frames["draw_submitted"]
    coalesced = sorted(prepared - drawn)
    repeated_observations = 0
    previous = {}
    for event in sorted(native, key=lambda e: e.get("t_us", 0)):
        if event.get("event") != "texture_sample":
            continue
        engine, frame = event["engine"], event["frame"]
        if frame and previous.get(engine) == frame:
            repeated_observations += 1
        previous[engine] = frame

    position_anomalies, last_positions = [], {}
    for event in sorted(dart, key=lambda e: e.get("t_us", 0)):
        if event.get("event") != "snapshot" or not event.get("playing"):
            continue
        for item in event.get("samples", []):
            key = (event["engine"], item["id"], item["time"])
            prior = last_positions.get(key)
            if prior and event["media_s"] > prior[0]:
                dx = item["x"] - prior[1]
                if abs(dx) < .0001 or (item["type"] == 1 and dx > .001) or (item["type"] == 6 and dx < -.001):
                    position_anomalies.append({"engine": event["engine"], "frame": event["frame"], "item": item["id"], "dx": dx})
            last_positions[key] = (event["media_s"], item["x"])

    return {
        "loss": dict(loss), "stages": stages, "gaps": gaps,
        "longest_stage_samples": sorted(long_frames, key=lambda e: e["duration_ms"], reverse=True)[:25],
        "prepared_without_draw": {"count": len(coalesced), "first_20": coalesced[:20]},
        "repeated_latest_completion_at_texture_callback": repeated_observations,
        "position_anomalies": position_anomalies[:30],
        "limits": [
            "Startup, pause, seek, and empty scenes can create legitimate gaps; correlate with the reported stutter interval.",
            "Native and Dart clock origins are separate; durations never subtract timestamps across domains.",
            "gpu_completion_latency includes callback dispatch latency; it is not a GPU timestamp measurement.",
            "Texture callbacks report latest observed completion, not the identity of pixels sampled or actual Present.",
            "Prepared frames without a draw can be coalesced, failed, or at the truncated end of capture.",
        ],
    }


def read_records(path):
    records, invalid = [], 0
    with Path(path).open(encoding="utf-8") as source:
        for line in source:
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                invalid += 1  # A terminated process can leave a partial final line.
    return records, invalid


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("trace", type=Path)
    args = parser.parse_args()
    records, invalid = read_records(args.trace)
    report = analyze(records)
    report["invalid_lines"] = invalid
    output = args.trace.with_suffix(".summary.json")
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(output)
