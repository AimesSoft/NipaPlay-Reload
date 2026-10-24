#!/bin/sh
# The tool sequence the trace drives is trace-script.json: see trace.py.
export TRACE_COMPACT=1
exec python3 "$(dirname "$0")/trace.py"
