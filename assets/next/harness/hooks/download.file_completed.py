#!/usr/bin/env python3
"""Editable subscription completion hook; no filename-based identity guesses."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import patrol
from subscription_io import emit

if __name__ == "__main__":
    emit(lambda: patrol.main(["--complete"]))
