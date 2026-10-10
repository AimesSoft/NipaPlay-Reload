const SERVICE: &str = "com.nipaplay.credential-vault.v1";

pub(crate) struct VaultService;

impl VaultService {
    fn account(namespace: &str, key: &str) -> Result<String, String> {
        if namespace.is_empty() || key.is_empty() || namespace.contains('\0') || key.contains('\0')
        {
            return Err("invalid_reference".into());
        }
        // Length prefix keeps arbitrary namespaces and keys unambiguous.
        Ok(format!("{}:{}{}", namespace.len(), namespace, key))
    }

    #[cfg(any(
        target_os = "macos",
        target_os = "windows",
        all(target_os = "linux", not(feature = "ohos"))
    ))]
    fn entry(namespace: &str, key: &str) -> Result<keyring::Entry, String> {
        let account = Self::account(namespace, key)?;
        keyring::Entry::new(SERVICE, &account).map_err(Self::error)
    }

    #[cfg(any(
        target_os = "macos",
        target_os = "windows",
        all(target_os = "linux", not(feature = "ohos"))
    ))]
    fn error(error: keyring::Error) -> String {
        // Platform error descriptions may contain credential material.
        match error {
            keyring::Error::NoEntry => "not_found",
            keyring::Error::NoStorageAccess(_) => "storage_access_denied",
            keyring::Error::PlatformFailure(_) => "system_vault_unavailable",
            keyring::Error::Ambiguous(_) => "ambiguous_reference",
            _ => "vault_operation_failed",
        }
        .into()
    }

    pub(crate) fn read(namespace: &str, key: &str) -> Result<Option<String>, String> {
        #[cfg(any(
            target_os = "macos",
            target_os = "windows",
            all(target_os = "linux", not(feature = "ohos"))
        ))]
        return Self::read_entry(&Self::entry(namespace, key)?);
        #[cfg(not(any(
            target_os = "macos",
            target_os = "windows",
            all(target_os = "linux", not(feature = "ohos"))
        )))]
        {
            Self::account(namespace, key)?;
            Err("unsupported_platform".into())
        }
    }

    #[cfg(any(
        target_os = "macos",
        target_os = "windows",
        all(target_os = "linux", not(feature = "ohos"))
    ))]
    fn read_entry(entry: &keyring::Entry) -> Result<Option<String>, String> {
        match entry.get_password() {
            Ok(value) => Ok(Some(value)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(error) => Err(Self::error(error)),
        }
    }

    pub(crate) fn write(namespace: &str, key: &str, secret: &str) -> Result<(), String> {
        #[cfg(any(
            target_os = "macos",
            target_os = "windows",
            all(target_os = "linux", not(feature = "ohos"))
        ))]
        return Self::entry(namespace, key)?
            .set_password(secret)
            .map_err(Self::error);
        #[cfg(not(any(
            target_os = "macos",
            target_os = "windows",
            all(target_os = "linux", not(feature = "ohos"))
        )))]
        {
            Self::account(namespace, key)?;
            let _ = secret;
            Err("unsupported_platform".into())
        }
    }

    pub(crate) fn delete(namespace: &str, key: &str) -> Result<(), String> {
        #[cfg(any(
            target_os = "macos",
            target_os = "windows",
            all(target_os = "linux", not(feature = "ohos"))
        ))]
        return Self::delete_entry(&Self::entry(namespace, key)?);
        #[cfg(not(any(
            target_os = "macos",
            target_os = "windows",
            all(target_os = "linux", not(feature = "ohos"))
        )))]
        {
            Self::account(namespace, key)?;
            Err("unsupported_platform".into())
        }
    }

    #[cfg(any(
        target_os = "macos",
        target_os = "windows",
        all(target_os = "linux", not(feature = "ohos"))
    ))]
    fn delete_entry(entry: &keyring::Entry) -> Result<(), String> {
        match entry.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(error) => Err(Self::error(error)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reference_boundaries() {
        assert_ne!(
            VaultService::account("a", "bc").unwrap(),
            VaultService::account("ab", "c").unwrap()
        );
        assert!(VaultService::account("", "key").is_err());
        assert!(VaultService::account("ns", "\0").is_err());
    }
    #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
    #[test]
    fn missing_and_deleted_entries_are_idempotent() {
        let entry =
            keyring::Entry::new_with_credential(Box::new(keyring::mock::MockCredential::default()));
        assert_eq!(VaultService::read_entry(&entry).unwrap(), None);
        entry.set_password("test-only-秘密").unwrap();
        assert_eq!(
            VaultService::read_entry(&entry).unwrap().as_deref(),
            Some("test-only-秘密")
        );
        VaultService::delete_entry(&entry).unwrap();
        VaultService::delete_entry(&entry).unwrap();
        assert_eq!(VaultService::read_entry(&entry).unwrap(), None);
    }
}
