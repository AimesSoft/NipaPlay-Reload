"""Exercise the workflow-built Windows DLL, without Flutter or video playback.

This measures only the native path. It cannot reproduce or rule out compositor,
video contention, or Ticker stalls in the player's real workload.
"""
import argparse
import ctypes as c
import json
import os
from pathlib import Path
import time


def run(dll_path, output, hz=180, seconds=5, count=60):
    output = output.resolve()
    if output.exists():
        raise FileExistsError(output)
    os.environ["NIPAPLAY_DFM_TRACE"] = str(output)
    dll = c.CDLL(str(dll_path.resolve()))
    dll.next2_diagnostics_enabled.restype = c.c_uint8
    if dll.next2_diagnostics_enabled() != 1:
        raise RuntimeError("diagnostics did not start")
    dll.next2_engine_create.argtypes = [c.c_uint32, c.c_uint32]
    dll.next2_engine_create.restype = c.c_uint64
    dll.next2_engine_create_dxgi_shared_texture.argtypes = [
        c.c_uint64, c.c_uint32, c.c_uint32, c.POINTER(c.c_size_t),
        c.POINTER(c.c_uint32), c.POINTER(c.c_uint32)]
    dll.next2_engine_create_dxgi_shared_texture.restype = c.c_uint8
    dll.next2_engine_set_frame_traced.argtypes = [
        c.c_uint64, c.c_char_p, c.c_float, c.c_float, c.c_uint8,
        c.c_float, c.c_char_p, c.c_char_p, c.c_uint64]
    dll.next2_engine_set_frame_traced.restype = c.c_uint8
    dll.next2_engine_dispose.argtypes = [c.c_uint64]
    dll.next2_engine_dispose.restype = None
    width, height = 1920, 1080  # 1280x720 at 1.5x supersampling
    engine = dll.next2_engine_create(width, height)
    if not engine:
        raise RuntimeError("engine creation failed")
    shared, out_width, out_height = c.c_size_t(), c.c_uint32(), c.c_uint32()
    try:
        if not dll.next2_engine_create_dxgi_shared_texture(
                engine, width, height, c.byref(shared), c.byref(out_width), c.byref(out_height)):
            raise RuntimeError("DXGI target creation failed")
        start = time.perf_counter()
        target = start
        elapsed_calls = []
        for frame in range(1, int(hz * seconds) + 1):
            delay = target - time.perf_counter()
            if delay > 0:
                time.sleep(delay)
            t = time.perf_counter() - start
            payload = json.dumps({"motion_mode": "vsync_snapshot", "items": [
                {"text": f"trace {i:02d}", "x": (i % 5) * 360 - (t * 150) % 300,
                 "y": (i // 5) * 50, "color_argb": -1, "scroll_speed": -150}
                for i in range(count)
            ]}).encode()
            before = time.perf_counter()
            if not dll.next2_engine_set_frame_traced(engine, payload, 36, 1, 1, 1, b"", b"", frame):
                raise RuntimeError(f"frame {frame} rejected")
            elapsed_calls.append(time.perf_counter() - before)
            # Never synthesize a catch-up burst after glyph warm-up or a stall.
            target = max(target + 1 / hz, time.perf_counter())
        time.sleep(1.2)  # Allow the last GPU callback and buffered trace to flush.
        print(json.dumps({"frames": len(elapsed_calls), "seconds": seconds,
                          "target_hz": hz, "items": count,
                          "max_ffi_call_ms": max(elapsed_calls) * 1000,
                          "trace": str(output)}))
    finally:
        dll.next2_engine_dispose(engine)
        if shared.value:
            close_handle = c.WinDLL("kernel32", use_last_error=True).CloseHandle
            close_handle.argtypes = [c.c_void_p]
            close_handle.restype = c.c_int
            close_handle(shared.value)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("dll", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--seconds", type=int, default=5)
    args = parser.parse_args()
    run(args.dll, args.output, seconds=args.seconds)
