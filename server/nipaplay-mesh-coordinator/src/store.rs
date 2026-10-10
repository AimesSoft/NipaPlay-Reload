//! SQLite-backed control-plane state.
//!
//! Only control-plane rows live here: device registration, address candidates,
//! certificate bookkeeping and the revocation epoch. No media or task traffic
//! ever reaches this database.

use std::{
    path::Path,
    sync::{Arc, Mutex},
};

use rusqlite::{params, Connection, OptionalExtension, TransactionBehavior};

use crate::error::{ApiError, ErrorCode};

impl From<rusqlite::Error> for ApiError {
    fn from(_: rusqlite::Error) -> Self {
        ApiError::internal("数据库操作失败")
    }
}

fn require_active(conn: &Connection, account_id: &str, device_id: &str) -> Result<(), ApiError> {
    let revoked: Option<Option<i64>> = conn
        .query_row(
            "SELECT revoked_at FROM devices WHERE account_id = ?1 AND device_id = ?2",
            params![account_id, device_id],
            |row| row.get(0),
        )
        .optional()?;
    match revoked {
        Some(None) => Ok(()),
        Some(Some(_)) => Err(ApiError::new(ErrorCode::DeviceRevoked, "设备已被吊销")),
        None => Err(ApiError::new(ErrorCode::DeviceNotFound, "设备未注册")),
    }
}

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
            CREATE TABLE IF NOT EXISTS possession_proofs (
                public_key BLOB NOT NULL,
                nonce TEXT NOT NULL,
                seen_at INTEGER NOT NULL,
                PRIMARY KEY (public_key, nonce)
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

    pub fn consume_proof(
        &self,
        public_key: &[u8],
        nonce: &str,
        now: i64,
    ) -> Result<bool, ApiError> {
        let mut conn = self.lock();
        let tx = conn
            .transaction()
            .map_err(|e| ApiError::internal(e.to_string()))?;
        tx.execute(
            "DELETE FROM possession_proofs WHERE seen_at < ?1",
            params![now - 600],
        )
        .map_err(|e| ApiError::internal(e.to_string()))?;
        let changed = tx.execute("INSERT OR IGNORE INTO possession_proofs (public_key, nonce, seen_at) VALUES (?1, ?2, ?3)",
            params![public_key, nonce, now]).map_err(|e| ApiError::internal(e.to_string()))?;
        tx.commit().map_err(|e| ApiError::internal(e.to_string()))?;
        Ok(changed == 1)
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
    pub fn upsert_device(&self, device: DeviceUpsert<'_>) -> Result<(), ApiError> {
        let mut conn = self.lock();
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
        let existing: Option<(String, Vec<u8>, Option<i64>)> = tx
            .query_row(
                "SELECT account_id, public_key, revoked_at FROM devices WHERE device_id = ?1",
                params![device.device_id],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .optional()?;
        if let Some((account, key, revoked)) = existing {
            if account != device.account_id || key != device.public_key {
                return Err(ApiError::new(ErrorCode::DeviceConflict, "设备身份冲突"));
            }
            if revoked.is_some() {
                return Err(ApiError::new(ErrorCode::DeviceRevoked, "设备已被吊销"));
            }
        }
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
        )?;
        tx.execute(
            "INSERT INTO certificates (device_id, issued_at, expires_at) VALUES (?1, ?2, ?3)",
            params![device.device_id, device.now, device.cert_expires_at],
        )?;
        tx.commit()?;
        Ok(())
    }

    /// Records a renewed certificate without touching device metadata.
    pub fn record_renewal(
        &self,
        account_id: &str,
        device_id: &str,
        now: i64,
        cert_expires_at: i64,
    ) -> Result<(), ApiError> {
        let mut conn = self.lock();
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
        require_active(&tx, account_id, device_id)?;
        tx.execute(
            "UPDATE devices SET last_seen_at = ?2 WHERE device_id = ?1",
            params![device_id, now],
        )?;
        tx.execute(
            "INSERT INTO certificates (device_id, issued_at, expires_at) VALUES (?1, ?2, ?3)",
            params![device_id, now, cert_expires_at],
        )?;
        tx.commit()?;
        Ok(())
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

    #[cfg(test)]
    pub fn list_devices(&self, account_id: &str) -> Result<Vec<DeviceRecord>, String> {
        let conn = self.lock();
        list_devices_at(&conn, account_id).map_err(|error| error.to_string())
    }

    pub fn device_snapshot(&self, account_id: &str) -> Result<(Vec<DeviceRecord>, i64), ApiError> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        let devices = list_devices_at(&tx, account_id)?;
        let epoch = tx.query_row(
            "SELECT COALESCE((SELECT revocation_epoch FROM accounts WHERE account_id = ?1), 0)",
            params![account_id],
            |row| row.get(0),
        )?;
        tx.commit()?;
        Ok((devices, epoch))
    }

    /// Marks a device revoked, bumps its account's revocation epoch, and drops
    /// the device's address candidates, all in one transaction.
    pub fn revoke_device(
        &self,
        account_id: &str,
        device_id: &str,
        now: i64,
    ) -> Result<i64, ApiError> {
        let mut conn = self.lock();
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
        let belongs: bool = tx.query_row(
            "SELECT EXISTS(SELECT 1 FROM devices WHERE account_id = ?1 AND device_id = ?2)",
            params![account_id, device_id],
            |row| row.get(0),
        )?;
        if !belongs {
            return Err(ApiError::new(ErrorCode::DeviceNotFound, "设备未注册"));
        }
        tx.execute(
            "UPDATE devices SET revoked_at = ?2 WHERE device_id = ?1 AND revoked_at IS NULL",
            params![device_id, now],
        )?;
        tx.execute(
            "DELETE FROM addresses WHERE device_id = ?1",
            params![device_id],
        )?;
        tx.execute(
            r#"INSERT INTO accounts (account_id, revocation_epoch) VALUES (?1, 1)
               ON CONFLICT(account_id) DO UPDATE SET revocation_epoch = revocation_epoch + 1"#,
            params![account_id],
        )?;
        let epoch = tx.query_row(
            "SELECT revocation_epoch FROM accounts WHERE account_id = ?1",
            params![account_id],
            |row| row.get(0),
        )?;
        tx.commit()?;
        Ok(epoch)
    }

    pub fn address_snapshot(
        &self,
        account_id: &str,
        device_id: &str,
        now: i64,
    ) -> Result<Vec<AddressRecord>, ApiError> {
        let mut conn = self.lock();
        let tx = conn.transaction()?;
        require_active(&tx, account_id, device_id)?;
        let records = addresses_at(&tx, device_id, now)?;
        tx.commit()?;
        Ok(records)
    }

    /// Replaces the stored address candidates for a device.
    pub fn replace_addresses(
        &self,
        account_id: &str,
        device_id: &str,
        addresses: &[AddressRecord],
        now: i64,
    ) -> Result<(), ApiError> {
        let mut conn = self.lock();
        let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
        require_active(&tx, account_id, device_id)?;
        tx.execute(
            "DELETE FROM addresses WHERE device_id = ?1",
            params![device_id],
        )?;
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
            )?;
        }
        tx.execute(
            "UPDATE devices SET last_seen_at = ?2 WHERE device_id = ?1",
            params![device_id, now],
        )?;
        tx.commit()?;
        Ok(())
    }

    #[cfg(test)]
    pub fn addresses(&self, device_id: &str, now: i64) -> Result<Vec<AddressRecord>, String> {
        addresses_at(&self.lock(), device_id, now).map_err(|error| error.to_string())
    }

    /// Deletes address rows that have expired.
    pub fn prune_expired_addresses(&self, now: i64) -> Result<usize, String> {
        self.lock()
            .execute("DELETE FROM addresses WHERE expires_at <= ?1", params![now])
            .map_err(|error| error.to_string())
    }
}

fn list_devices_at(conn: &Connection, account_id: &str) -> rusqlite::Result<Vec<DeviceRecord>> {
    let mut statement = conn.prepare(
        r#"SELECT account_id, device_id, public_key, name, platform,
                          created_at, last_seen_at, revoked_at
                   FROM devices WHERE account_id = ?1 ORDER BY created_at"#,
    )?;
    let rows = statement.query_map(params![account_id], row_to_device)?;
    rows.collect()
}

fn addresses_at(
    conn: &Connection,
    device_id: &str,
    now: i64,
) -> rusqlite::Result<Vec<AddressRecord>> {
    let mut statement = conn.prepare(
        r#"SELECT kind, host, port, priority, expires_at, updated_at
                   FROM addresses
                   WHERE device_id = ?1 AND expires_at > ?2
                   ORDER BY priority DESC, updated_at DESC"#,
    )?;
    let rows = statement.query_map(params![device_id, now], |row| {
        Ok(AddressRecord {
            kind: row.get(0)?,
            host: row.get(1)?,
            port: row.get(2)?,
            priority: row.get(3)?,
            expires_at: row.get(4)?,
            updated_at: row.get(5)?,
        })
    })?;
    rows.collect()
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
        assert_eq!(store.revoke_device("acct-1", "dev-1", 10).unwrap(), 1);
        assert_eq!(store.revocation_epoch("acct-1").unwrap(), 1);
        assert_eq!(store.revocation_epoch("acct-2").unwrap(), 0);
        assert!(store.device("dev-1").unwrap().unwrap().revoked_at.is_some());
        // Re-revoking is a no-op for state but still advances the epoch.
        assert_eq!(store.revoke_device("acct-1", "dev-1", 11).unwrap(), 2);
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
                "acct-1",
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

        store.revoke_device("acct-1", "dev-1", 20).unwrap();
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
                "acct-1",
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

        store.replace_addresses("acct-1", "dev-1", &[], 5).unwrap();
        assert!(store.addresses("dev-1", 50).unwrap().is_empty());
    }

    fn fixture_device<'a>(account: &'a str) -> DeviceUpsert<'a> {
        DeviceUpsert {
            account_id: account,
            device_id: "dev-shared",
            public_key: &[9; 32],
            name: "Mac",
            platform: "macos",
            app_version: "1",
            now: 100,
            cert_expires_at: 200,
        }
    }

    fn fixture_address(host: &str) -> AddressRecord {
        AddressRecord {
            kind: "lan".to_owned(),
            host: host.to_owned(),
            port: 1180,
            priority: 1,
            expires_at: 300,
            updated_at: 100,
        }
    }

    #[test]
    fn simultaneous_registration_cannot_issue_for_two_accounts() {
        let store = store();
        let barrier = Arc::new(std::sync::Barrier::new(2));
        let threads: Vec<_> = ["account-a", "account-b"]
            .into_iter()
            .map(|account| {
                let store = store.clone();
                let barrier = barrier.clone();
                std::thread::spawn(move || {
                    assert!(store.device("dev-shared").unwrap().is_none());
                    barrier.wait();
                    store.upsert_device(fixture_device(account))
                })
            })
            .collect();
        let results: Vec<_> = threads
            .into_iter()
            .map(|thread| thread.join().unwrap())
            .collect();
        assert_eq!(results.iter().filter(|result| result.is_ok()).count(), 1);
        assert_eq!(
            results
                .iter()
                .find_map(|result| result.as_ref().err())
                .unwrap()
                .code,
            ErrorCode::DeviceConflict
        );
        let count: i64 = store
            .lock()
            .query_row("SELECT COUNT(*) FROM certificates", [], |row| row.get(0))
            .unwrap();
        assert_eq!(count, 1);
    }

    #[test]
    fn a_stale_precheck_cannot_write_after_revocation() {
        let store = store();
        store.upsert_device(fixture_device("account-a")).unwrap();
        let stale = store.device("dev-shared").unwrap().unwrap();
        assert!(stale.revoked_at.is_none());
        store.revoke_device("account-a", "dev-shared", 110).unwrap();
        assert_eq!(
            store
                .record_renewal(&stale.account_id, &stale.device_id, 120, 220)
                .unwrap_err()
                .code,
            ErrorCode::DeviceRevoked
        );
        assert_eq!(
            store
                .replace_addresses(
                    &stale.account_id,
                    &stale.device_id,
                    &[fixture_address("192.168.1.1")],
                    120
                )
                .unwrap_err()
                .code,
            ErrorCode::DeviceRevoked
        );
        assert_eq!(
            store
                .upsert_device(fixture_device("account-a"))
                .unwrap_err()
                .code,
            ErrorCode::DeviceRevoked
        );
        assert_eq!(
            store
                .address_snapshot("account-a", "dev-shared", 120)
                .unwrap_err()
                .code,
            ErrorCode::DeviceRevoked
        );
        assert!(store.addresses("dev-shared", 120).unwrap().is_empty());
        let count: i64 = store
            .lock()
            .query_row("SELECT COUNT(*) FROM certificates", [], |row| row.get(0))
            .unwrap();
        assert_eq!(count, 1);
    }

    #[test]
    fn concurrent_report_and_revoke_leave_no_addresses_and_consistent_snapshot() {
        let store = store();
        store.upsert_device(fixture_device("account-a")).unwrap();
        let barrier = Arc::new(std::sync::Barrier::new(2));
        let report = {
            let store = store.clone();
            let barrier = barrier.clone();
            std::thread::spawn(move || {
                barrier.wait();
                store.replace_addresses(
                    "account-a",
                    "dev-shared",
                    &[fixture_address("192.168.1.1")],
                    110,
                )
            })
        };
        barrier.wait();
        store.revoke_device("account-a", "dev-shared", 110).unwrap();
        if let Err(error) = report.join().unwrap() {
            assert_eq!(error.code, ErrorCode::DeviceRevoked);
        }
        assert!(store.addresses("dev-shared", 120).unwrap().is_empty());
        let (devices, epoch) = store.device_snapshot("account-a").unwrap();
        assert_eq!(epoch, 1);
        assert!(devices[0].revoked_at.is_some());
    }

    #[test]
    fn failed_replacement_rolls_back_and_sql_metacharacters_remain_data() {
        let store = store();
        let account = "'; DROP TABLE devices; --";
        store.upsert_device(fixture_device(account)).unwrap();
        let address = fixture_address("192.168.1.1");
        store
            .replace_addresses(account, "dev-shared", std::slice::from_ref(&address), 110)
            .unwrap();
        assert!(store
            .replace_addresses(account, "dev-shared", &[address.clone(), address], 120)
            .is_err());
        let records = store.addresses("dev-shared", 120).unwrap();
        assert_eq!(records.len(), 1);
        assert_eq!(records[0].updated_at, 110);
        assert_eq!(store.list_devices(account).unwrap().len(), 1);
        assert_eq!(
            store.device("dev-shared").unwrap().unwrap().last_seen_at,
            110
        );
        assert_eq!(
            store
                .revoke_device("other-account", "dev-shared", 130)
                .unwrap_err()
                .code,
            ErrorCode::DeviceNotFound
        );
    }
}
