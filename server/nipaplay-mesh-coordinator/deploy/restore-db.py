#!/usr/bin/env python3
"""Put a backup of the coordinator database back, without letting any account's
revocation epoch go backwards and without un-revoking anyone.

  restore-db.py BACKUP [--db PATH]        (stop the service first, start it after)

Clients refuse a revocation epoch lower than the one they have seen, and a device
revoked after the backup was taken must stay revoked. So, on top of the plain copy:
  * every account's epoch becomes max(backup, database being replaced) + 1
    (the increase also makes every client re-read its device list);
  * devices revoked in the database being replaced are revoked again, and their
    address candidates dropped.
The database being replaced is kept next to it as mesh.db.pre-restore-<time>.
Devices registered after the backup are not in the restored database; they
register again the next time they start with an account token.
"""
import argparse, os, shutil, sqlite3, sys, time

parser = argparse.ArgumentParser()
parser.add_argument("backup")
parser.add_argument("--db", default="/var/lib/nipaplay-mesh-coordinator/mesh.db")
args = parser.parse_args()

if not os.path.isfile(args.backup):
    sys.exit(f"{args.backup} not found")
probe = sqlite3.connect(f"file:{args.backup}?mode=ro", uri=True)
if probe.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
    sys.exit("the backup does not pass integrity_check")
probe.close()

current_epochs, current_revoked = {}, {}
if os.path.exists(args.db):
    current = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    current_epochs = dict(current.execute("SELECT account_id, revocation_epoch FROM accounts"))
    current_revoked = {
        row[0]: row[1]
        for row in current.execute("SELECT device_id, revoked_at FROM devices WHERE revoked_at IS NOT NULL")
    }
    current.close()
    keep = f"{args.db}.pre-restore-{time.strftime('%Y%m%d-%H%M%S')}"
    shutil.move(args.db, keep)
    for suffix in ("-wal", "-shm"):
        if os.path.exists(args.db + suffix):
            shutil.move(args.db + suffix, keep + suffix)
    print("replaced database kept as", keep)

shutil.copy2(args.backup, args.db)
conn = sqlite3.connect(args.db)
with conn:
    backup_epochs = dict(conn.execute("SELECT account_id, revocation_epoch FROM accounts"))
    print("epochs in the backup:        ", backup_epochs)
    print("epochs before the restore:   ", current_epochs)
    for account in set(backup_epochs) | set(current_epochs):
        epoch = max(backup_epochs.get(account, 0), current_epochs.get(account, 0)) + 1
        conn.execute(
            "INSERT INTO accounts (account_id, revocation_epoch) VALUES (?1, ?2) "
            "ON CONFLICT(account_id) DO UPDATE SET revocation_epoch = ?2",
            (account, epoch),
        )
    for device_id, revoked_at in current_revoked.items():
        conn.execute("UPDATE devices SET revoked_at = ?2 WHERE device_id = ?1 AND revoked_at IS NULL", (device_id, revoked_at))
        conn.execute("DELETE FROM addresses WHERE device_id = ?1", (device_id,))
    after = dict(conn.execute("SELECT account_id, revocation_epoch FROM accounts"))
    print("epochs after the restore:    ", after)
    for account, before in current_epochs.items():
        assert after[account] >= before, f"epoch of {account} went backwards"
    print("devices kept revoked:", len(current_revoked))
conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
conn.close()
st = os.stat(os.path.dirname(args.db))
os.chown(args.db, st.st_uid, st.st_gid)
os.chmod(args.db, 0o600)
print("restored", args.db, "- start the service now")
