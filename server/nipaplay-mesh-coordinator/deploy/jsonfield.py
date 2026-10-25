#!/usr/bin/env python3
"""jsonfield.py <field> : print one top-level field of the JSON on stdin."""
import json, sys
value = json.load(sys.stdin)[sys.argv[1]]
print(value if isinstance(value, str) else json.dumps(value))
