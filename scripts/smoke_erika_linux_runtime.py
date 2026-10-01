#!/usr/bin/env python3
"""Load the release runtime and exercise real software decode and GIF export."""
import ctypes as c
from pathlib import Path
import subprocess
import sys
import tempfile

library_dir = Path(sys.argv[1]).resolve()
lib = c.CDLL(str(library_dir / 'liberika_capi.so'))
lib.erika_create.argtypes = []
lib.erika_create.restype = c.c_void_p
lib.erika_open.argtypes = [c.c_void_p, c.c_char_p]
lib.erika_stop.argtypes = [c.c_void_p]
lib.erika_close.argtypes = [c.c_void_p]
lib.erika_destroy.argtypes = [c.c_void_p]
lib.erika_destroy.restype = None
lib.erika_last_error_message.restype = c.c_void_p
lib.erika_string_free.argtypes = [c.c_void_p]
lib.erika_string_free.restype = None

def check(status):
    if status:
        error = lib.erika_last_error_message()
        message = c.string_at(error).decode() if error else str(status)
        if error:
            lib.erika_string_free(error)
        raise RuntimeError(message)

class GifOptions(c.Structure):
    _fields_ = [
        ('input_uri', c.c_char_p), ('output_path', c.c_char_p),
        ('start_millis', c.c_uint64), ('end_millis', c.c_uint64),
        ('frames_per_second', c.c_uint32), ('output_width', c.c_uint32),
        ('output_height', c.c_uint32), ('quality', c.c_int32),
        ('loop_count', c.c_int32), ('overwrite', c.c_bool),
        ('headers', c.c_void_p), ('header_count', c.c_size_t),
        ('http_read_ahead_bytes', c.c_uint64), ('reserved', c.c_uint64 * 3),
    ]

class GifResult(c.Structure):
    _fields_ = [
        ('width', c.c_uint32), ('height', c.c_uint32),
        ('frame_count', c.c_uint64), ('file_size', c.c_uint64),
    ]

lib.erika_export_gif.argtypes = [c.POINTER(GifOptions), c.POINTER(GifResult)]
with tempfile.TemporaryDirectory(prefix='nipaplay-erika-smoke-') as temp:
    source = Path(temp) / 'fixture.mp4'
    output = Path(temp) / 'fixture.gif'
    subprocess.run([
        'ffmpeg', '-v', 'error', '-f', 'lavfi', '-i',
        'testsrc2=size=64x36:rate=10', '-t', '1', '-c:v', 'mpeg4', str(source),
    ], check=True)
    handle = lib.erika_create()
    if not handle:
        raise RuntimeError('erika_create returned NULL')
    try:
        check(lib.erika_open(handle, str(source).encode()))
        check(lib.erika_stop(handle))
        check(lib.erika_close(handle))
    finally:
        lib.erika_destroy(handle)
    options = GifOptions(
        input_uri=str(source).encode(), output_path=str(output).encode(),
        end_millis=1000, frames_per_second=10, output_width=32, output_height=18,
    )
    result = GifResult()
    check(lib.erika_export_gif(c.byref(options), c.byref(result)))
    if (result.width, result.height) != (32, 18) or result.frame_count == 0:
        raise RuntimeError(f'Invalid GIF result: {result.width}x{result.height}, {result.frame_count} frames')
    if output.read_bytes()[:6] not in (b'GIF87a', b'GIF89a'):
        raise RuntimeError('Output is not a GIF')
    print(f'Erika Linux runtime passed: open/stop/close and GIF export ({result.frame_count} frames).')
