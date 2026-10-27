#!/bin/sh
export LD_LIBRARY_PATH=/app/lib:/app/lib/nipaplay:/app/lib/ffmpeg${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
exec /app/bin/NipaPlay "$@"
