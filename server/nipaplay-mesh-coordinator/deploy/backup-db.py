#!/usr/bin/env python3
"""Consistent online backup of the coordinator's SQLite database.

  backup-db.py [--db PATH] [--to DIR] [--keep N]   backup now (the service may keep running)
  backup-db.py --check                             only check that python3 can do this

Uses SQLite's backup API, so a copy taken while the service writes is still a
complete database. Backups are named mesh-YYYYmmdd-HHMMSS.db in DIR (mode
0600) and only the newest N are kept. The database holds device public keys,
names and short-lived addresses; no tokens and no private keys.
"""
import argparse, glob, os, sqlite3, sys, time

parser = argparse.ArgumentParser()
parser.add_argument("--db", default="/var/lib/nipaplay-mesh-coordinator/mesh.db")
parser.add_argument("--to", default="/var/backups/nipaplay-mesh")
parser.add_argument("--keep", type=int, default=14)
parser.add_argument("--check", action="store_true")
args = parser.parse_args()

if args.check:
    print("python3 + sqlite3", sqlite3.sqlite_version)
    sys.exit(0)

os.makedirs(args.to, mode=0o700, exist_ok=True)
target = os.path.join(args.to, time.strftime("mesh-%Y%m%d-%H%M%S.db"))
source = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
destination = sqlite3.connect(target)
with destination:
    source.backup(destination)
# a single self-contained file: no -wal/-shm beside the backup
destination.execute("PRAGMA journal_mode=DELETE")
check = destination.execute("PRAGMA integrity_check").fetchone()[0]
epochs = destination.execute("SELECT account_id, revocation_epoch FROM accounts ORDER BY account_id").fetchall()
devices = destination.execute("SELECT count(*), sum(revoked_at IS NOT NULL) FROM devices").fetchone()
destination.close(); source.close()
os.chmod(target, 0o600)
for old in sorted(glob.glob(os.path.join(args.to, "mesh-*.db")))[: -args.keep]:
    os.remove(old)
print(f"backup {target} integrity={check} devices={devices[0]} revoked={devices[1] or 0} epochs={dict(epochs)}")
if check != "ok":
    sys.exit(1)
