//! SQLite-backed control-plane state.
//!
//! Only control-plane rows live here: device registration, address candidates,
//! certificate bookkeeping and the revocation epoch. No media or task traffic
//! ever reaches this database.

use std::{
    path::Path,
    sync::{Arc, Mutex},
};

use rusqlite::{params, Connection, OptionalExtension};

#[derive(Clone)]
pub struct Store {
    conn: Arc<Mutex<Connection>>,
}

#[derive(Debug, Clone)]
pub struct DeviceRecord {
    pub account_id: String,
    pub device_id: String,
    pub public_key: Vec<u8>,
    pub name: String,
    pub platform: String,
    pub created_at: i64,
    pub last_seen_at: i64,
    pub revoked_at: Option<i64>,
}

/// Fields written when a device registers or renews.
pub struct DeviceUpsert<'a> {
    pub account_id: &'a str,
    pub device_id: &'a str,
    pub public_key: &'a [u8],
    pub name: &'a str,
    pub platform: &'a str,
    pub app_version: &'a str,
    pub now: i64,
    pub cert_expires_at: i64,
}

#[derive(Debug, Clone)]
pub struct AddressRecord {
    pub kind: String,
    pub host: String,
    pub port: u16,
    pub priority: i64,
    pub expires_at: i64,
    pub updated_at: i64,
}

impl Store {
    pub fn open(path: &Path) -> Result<Self, String> {
        let conn = Connection::open(path)
            .map_err(|error| format!("failed to open {}: {error}", path.display()))?;
        Self::from_connection(conn)
    }

    #[cfg(test)]
    pub fn open_in_memory() -> Result<Self, String> {
        let conn = Connection::open_in_memory().map_err(|error| error.to_string())?;
        Self::from_connection(conn)
    }

    fn from_connection(conn: Connection) -> Result<Self, String> {
        conn.pragma_update(None, "journal_mode", "WAL")
            .map_err(|error| error.to_string())?;
        conn.pragma_update(None, "foreign_keys", "ON")
            .map_err(|error| error.to_string())?;
        conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS devices (
                device_id    TEXT PRIMARY KEY,
                account_id   TEXT NOT NULL,
                public_key   BLOB NOT NULL,
                name         TEXT NOT NULL,
                platform     TEXT NOT NULL,
                app_version  TEXT NOT NULL,
                created_at   INTEGER NOT NULL,
                last_seen_at INTEGER NOT NULL,
                revoked_at   INTEGER
            );
            CREATE INDEX IF NOT EXISTS devices_account ON devices (account_id);

            CREATE TABLE IF NOT EXISTS addresses (
                device_id  TEXT NOT NULL,
                kind       TEXT NOT NULL,
                host       TEXT NOT NULL,
                port       INTEGER NOT NULL,
                priority   INTEGER NOT NULL,
                expires_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                PRIMARY KEY (device_id, kind, host, port)
            );

            CREATE TABLE IF NOT EXISTS certificates (
                device_id  TEXT NOT NULL,
                issued_at  INTEGER NOT NULL,
                expires_at INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS certificates_device ON certificates (device_id);

            CREATE TABLE IF NOT EXISTS accounts (
                account_id       TEXT PRIMARY KEY,
                revocation_epoch INTEGER NOT NULL DEFAULT 0
            );
            "#,
        )
        .map_err(|error| error.to_string())?;
        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
        })
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, Connection> {
        self.conn
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Current revocation epoch for an account (0 when the account has never
    /// revoked a device). Counting per account avoids leaking the platform-wide
    /// revocation volume.
    pub fn revocation_epoch(&self, account_id: &str) -> Result<i64, String> {
        self.lock()
            .query_row(
                "SELECT COALESCE(
                     (SELECT revocation_epoch FROM accounts WHERE account_id = ?1), 0)",
                params![account_id],
                |row| row.get::<_, i64>(0),
            )
            .map_err(|error| error.to_string())
    }

    /// Records a device and its freshly issued certificate in one transaction.
    pub fn upsert_device(&self, device: DeviceUpsert<'_>) -> Result<(), String> {
        let mut conn = self.lock();
        let tx = conn.transaction().map_err(|error| error.to_string())?;
        tx.execute(
            r#"
            INSERT INTO devices
                (device_id, account_id, public_key, name, platform, app_version,
                 created_at, last_seen_at, revoked_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7, NULL)
            ON CONFLICT(device_id) DO UPDATE SET
                name = excluded.name,
                platform = excluded.platform,
                app_version = excluded.app_version,
                last_seen_at = excluded.last_seen_at
            WHERE devices.account_id = excluded.account_id
            "#,
            params![
                device.device_id,
                device.account_id,
                device.public_key,
                device.name,
                device.platform,
                device.app_version,
                device.now
            ],
        )
        .map_err(|error| error.to_string())?;
        tx.execute(
            "INSERT INTO certificates (device_id, issued_at, expires_at) VALUES (?1, ?2, ?3)",
            params![device.device_id, device.now, device.cert_expires_at],
        )
        .map_err(|error| error.to_string())?;
        tx.commit().map_err(|error| error.to_string())
    }

    /// Records a renewed certificate without touching device metadata.
    pub fn record_renewal(
        &self,
        device_id: &str,
        now: i64,
        cert_expires_at: i64,
    ) -> Result<(), String> {
        let mut conn = self.lock();
        let tx = conn.transaction().map_err(|error| error.to_string())?;
        tx.execute(
            "UPDATE devices SET last_seen_at = ?2 WHERE device_id = ?1",
            params![device_id, now],
        )
        .map_err(|error| error.to_string())?;
        tx.execute(
            "INSERT INTO certificates (device_id, issued_at, expires_at) VALUES (?1, ?2, ?3)",
            params![device_id, now, cert_expires_at],
        )
        .map_err(|error| error.to_string())?;
        tx.commit().map_err(|error| error.to_string())
    }

    pub fn device(&self, device_id: &str) -> Result<Option<DeviceRecord>, String> {
        self.lock()
            .query_row(
                r#"SELECT account_id, device_id, public_key, name, platform,
                          created_at, last_seen_at, revoked_at
                   FROM devices WHERE device_id = ?1"#,
                params![device_id],
                row_to_device,
            )
            .optional()
            .map_err(|error| error.to_string())
    }

    pub fn list_devices(&self, account_id: &str) -> Result<Vec<DeviceRecord>, String> {
        let conn = self.lock();
        let mut statement = conn
            .prepare(
                r#"SELECT account_id, device_id, public_key, name, platform,
                          created_at, last_seen_at, revoked_at
                   FROM devices WHERE account_id = ?1 ORDER BY created_at"#,
            )
            .map_err(|error| error.to_string())?;
        let rows = statement
            .query_map(params![account_id], row_to_device)
            .map_err(|error| error.to_string())?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|error| error.to_string())
    }

    /// Marks a device revoked, bumps its account's revocation epoch, and drops
    /// the device's address candidates, all in one transaction.
    pub fn revoke_device(&self, device_id: &str, now: i64) -> Result<i64, String> {
        let mut conn = self.lock();
        let tx = conn.transaction().map_err(|error| error.to_string())?;
        let account_id: String = tx
            .query_row(
                "SELECT account_id FROM devices WHERE device_id = ?1",
                params![device_id],
                |row| row.get(0),
            )
            .map_err(|error| error.to_string())?;
        tx.execute(
            "UPDATE devices SET revoked_at = ?2 WHERE device_id = ?1 AND revoked_at IS NULL",
            params![device_id, now],
        )
        .map_err(|error| error.to_string())?;
        tx.execute(
            "DELETE FROM addresses WHERE device_id = ?1",
            params![device_id],
        )
        .map_err(|error| error.to_string())?;
        tx.execute(
            r#"INSERT INTO accounts (account_id, revocation_epoch) VALUES (?1, 1)
               ON CONFLICT(account_id) DO UPDATE
                   SET revocation_epoch = revocation_epoch + 1"#,
            params![account_id],
        )
        .map_err(|error| error.to_string())?;
        let epoch: i64 = tx
            .query_row(
                "SELECT revocation_epoch FROM accounts WHERE account_id = ?1",
                params![account_id],
                |row| row.get(0),
            )
            .map_err(|error| error.to_string())?;
        tx.commit().map_err(|error| error.to_string())?;
        Ok(epoch)
    }

    /// Replaces the stored address candidates for a device.
    pub fn replace_addresses(
        &self,
        device_id: &str,
        addresses: &[AddressRecord],
        now: i64,
    ) -> Result<(), String> {
        let mut conn = self.lock();
        let tx = conn.transaction().map_err(|error| error.to_string())?;
        tx.execute(
            "DELETE FROM addresses WHERE device_id = ?1",
            params![device_id],
        )
        .map_err(|error| error.to_string())?;
        for address in addresses {
            tx.execute(
                r#"INSERT INTO addresses
                       (device_id, kind, host, port, priority, expires_at, updated_at)
                   VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)"#,
                params![
                    device_id,
                    address.kind,
                    address.host,
                    address.port,
                    address.priority,
                    address.expires_at,
                    now
                ],
            )
            .map_err(|error| error.to_string())?;
        }
        tx.execute(
            "UPDATE devices SET last_seen_at = ?2 WHERE device_id = ?1",
            params![device_id, now],
        )
        .map_err(|error| error.to_string())?;
        tx.commit().map_err(|error| error.to_string())
    }

    pub fn addresses(&self, device_id: &str, now: i64) -> Result<Vec<AddressRecord>, String> {
        let conn = self.lock();
        let mut statement = conn
            .prepare(
                r#"SELECT kind, host, port, priority, expires_at, updated_at
                   FROM addresses
                   WHERE device_id = ?1 AND expires_at > ?2
                   ORDER BY priority DESC, updated_at DESC"#,
            )
            .map_err(|error| error.to_string())?;
        let rows = statement
            .query_map(params![device_id, now], |row| {
                Ok(AddressRecord {
                    kind: row.get(0)?,
                    host: row.get(1)?,
                    port: row.get(2)?,
                    priority: row.get(3)?,
                    expires_at: row.get(4)?,
                    updated_at: row.get(5)?,
                })
            })
            .map_err(|error| error.to_string())?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|error| error.to_string())
    }

    /// Deletes address rows that have expired.
    pub fn prune_expired_addresses(&self, now: i64) -> Result<usize, String> {
        self.lock()
            .execute("DELETE FROM addresses WHERE expires_at <= ?1", params![now])
            .map_err(|error| error.to_string())
    }
}

fn row_to_device(row: &rusqlite::Row<'_>) -> rusqlite::Result<DeviceRecord> {
    Ok(DeviceRecord {
        account_id: row.get(0)?,
        device_id: row.get(1)?,
        public_key: row.get(2)?,
        name: row.get(3)?,
        platform: row.get(4)?,
        created_at: row.get(5)?,
        last_seen_at: row.get(6)?,
        revoked_at: row.get(7)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> Store {
        Store::open_in_memory().unwrap()
    }

    #[test]
    fn registering_a_device_records_it_for_its_account() {
        let store = store();
        store
            .upsert_device(DeviceUpsert {
                account_id: "acct-1",
                device_id: "dev-1",
                public_key: &[7u8; 32],
                name: "Mac",
                platform: "macos",
                app_version: "1.0",
                now: 100,
                cert_expires_at: 200,
            })
            .unwrap();
        let devices = store.list_devices("acct-1").unwrap();
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].device_id, "dev-1");
        assert_eq!(devices[0].public_key, vec![7u8; 32]);
        assert!(devices[0].revoked_at.is_none());
        assert!(store.list_devices("acct-2").unwrap().is_empty());
    }

    #[test]
    fn re_registering_keeps_created_at_and_updates_metadata() {
        let store = store();
        store
            .upsert_device(DeviceUpsert {
                account_id: "acct-1",
                device_id: "dev-1",
                public_key: &[7u8; 32],
                name: "Mac",
                platform: "macos",
                app_version: "1.0",
                now: 100,
                cert_expires_at: 200,
            })
            .unwrap();
        store
            .upsert_device(DeviceUpsert {
                account_id: "acct-1",
                device_id: "dev-1",
                public_key: &[7u8; 32],
                name: "MacBook",
                platform: "macos",
                app_version: "1.1",
                now: 300,
                cert_expires_at: 400,
            })
            .unwrap();
        let device = store.device("dev-1").unwrap().unwrap();
        assert_eq!(device.created_at, 100);
        assert_eq!(device.last_seen_at, 300);
        assert_eq!(device.name, "MacBook");
    }

    #[test]
    fn revoking_bumps_only_the_owning_accounts_epoch() {
        let store = store();
        for (account, device) in [("acct-1", "dev-1"), ("acct-2", "dev-2")] {
            store
                .upsert_device(DeviceUpsert {
                    account_id: account,
                    device_id: device,
                    public_key: &[1u8; 32],
                    name: "Mac",
                    platform: "macos",
                    app_version: "1.0",
                    now: 1,
                    cert_expires_at: 2,
                })
                .unwrap();
        }
        assert_eq!(store.revocation_epoch("acct-1").unwrap(), 0);
        assert_eq!(store.revocation_epoch("acct-2").unwrap(), 0);
        assert_eq!(store.revoke_device("dev-1", 10).unwrap(), 1);
        assert_eq!(store.revocation_epoch("acct-1").unwrap(), 1);
        assert_eq!(store.revocation_epoch("acct-2").unwrap(), 0);
        assert!(store.device("dev-1").unwrap().unwrap().revoked_at.is_some());
        // Re-revoking is a no-op for state but still advances the epoch.
        assert_eq!(store.revoke_device("dev-1", 11).unwrap(), 2);
    }

    #[test]
    fn revoking_drops_the_devices_address_candidates() {
        let store = store();
        store
            .upsert_device(DeviceUpsert {
                account_id: "acct-1",
                device_id: "dev-1",
                public_key: &[1u8; 32],
                name: "Mac",
                platform: "macos",
                app_version: "1.0",
                now: 1,
                cert_expires_at: 2,
            })
            .unwrap();
        store
            .replace_addresses(
                "dev-1",
                &[AddressRecord {
                    kind: "lan".to_owned(),
                    host: "192.168.1.2".to_owned(),
                    port: 1180,
                    priority: 10,
                    expires_at: 10_000,
                    updated_at: 0,
                }],
                5,
            )
            .unwrap();
        assert_eq!(store.addresses("dev-1", 50).unwrap().len(), 1);

        store.revoke_device("dev-1", 20).unwrap();
        assert!(store.addresses("dev-1", 50).unwrap().is_empty());
    }

    #[test]
    fn addresses_replace_and_expire() {
        let store = store();
        store
            .upsert_device(DeviceUpsert {
                account_id: "acct-1",
                device_id: "dev-1",
                public_key: &[1u8; 32],
                name: "Mac",
                platform: "macos",
                app_version: "1.0",
                now: 1,
                cert_expires_at: 2,
            })
            .unwrap();
        store
            .replace_addresses(
                "dev-1",
                &[AddressRecord {
                    kind: "lan".to_owned(),
                    host: "192.168.1.2".to_owned(),
                    port: 1180,
                    priority: 10,
                    expires_at: 100,
                    updated_at: 0,
                }],
                5,
            )
            .unwrap();
        assert_eq!(store.addresses("dev-1", 50).unwrap().len(), 1);
        assert!(store.addresses("dev-1", 200).unwrap().is_empty());

        store.replace_addresses("dev-1", &[], 5).unwrap();
        assert!(store.addresses("dev-1", 50).unwrap().is_empty());
    }
}
