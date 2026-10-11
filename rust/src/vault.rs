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
        #[cfg(target_os = "macos")]
        return macos::read(&Self::account(namespace, key)?);
        #[cfg(any(target_os = "windows", all(target_os = "linux", not(feature = "ohos"))))]
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
        #[cfg(target_os = "macos")]
        return macos::write(&Self::account(namespace, key)?, secret);
        #[cfg(any(target_os = "windows", all(target_os = "linux", not(feature = "ohos"))))]
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
        #[cfg(target_os = "macos")]
        return macos::delete(&Self::account(namespace, key)?);
        #[cfg(any(target_os = "windows", all(target_os = "linux", not(feature = "ohos"))))]
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

// Use the same default-keychain generic-password APIs and account encoding as
// keyring, retaining OSStatus before keyring erases authorization error codes.
#[cfg(target_os = "macos")]
mod macos {
    use libc::c_void;
    use std::ptr;
    type Ref = *mut c_void;
    #[link(name = "Security", kind = "framework")]
    unsafe extern "C" {
        fn SecKeychainCopyDomainDefault(domain: u32, keychain: *mut Ref) -> i32;
        fn SecKeychainFindGenericPassword(
            keychain: Ref,
            service_len: u32,
            service: *const u8,
            account_len: u32,
            account: *const u8,
            length: *mut u32,
            data: *mut Ref,
            item: *mut Ref,
        ) -> i32;
        fn SecKeychainItemFreeContent(attributes: Ref, data: Ref) -> i32;
        fn SecKeychainItemModifyAttributesAndData(
            item: Ref,
            attributes: Ref,
            length: u32,
            data: *const u8,
        ) -> i32;
        fn SecKeychainAddGenericPassword(
            keychain: Ref,
            service_len: u32,
            service: *const u8,
            account_len: u32,
            account: *const u8,
            length: u32,
            data: *const u8,
            item: *mut Ref,
        ) -> i32;
        fn SecKeychainItemDelete(item: Ref) -> i32;
    }
    #[link(name = "CoreFoundation", kind = "framework")]
    unsafe extern "C" {
        fn CFRelease(value: Ref);
    }

    pub(super) fn error(status: i32) -> String {
        match status {
            -128 => "storage_authorization_cancelled", // errSecUserCanceled
            -25293 => "storage_access_denied",         // errSecAuthFailed
            -25308 => "storage_interaction_required",  // errSecInteractionNotAllowed
            -25291 | -25292 | -25294 | -25295 => "system_vault_unavailable",
            _ => "vault_operation_failed",
        }
        .into()
    }

    struct OwnedRef(Ref);
    impl Drop for OwnedRef {
        fn drop(&mut self) {
            unsafe {
                CFRelease(self.0);
            }
        }
    }
    fn default_keychain() -> Result<OwnedRef, String> {
        let mut value = ptr::null_mut();
        let status = unsafe { SecKeychainCopyDomainDefault(0, &mut value) };
        if status != 0 {
            return Err(error(status));
        }
        Ok(OwnedRef(value))
    }
    fn find(
        keychain: &OwnedRef,
        account: &str,
        length: *mut u32,
        data: *mut Ref,
        item: *mut Ref,
    ) -> i32 {
        unsafe {
            SecKeychainFindGenericPassword(
                keychain.0,
                super::SERVICE.len() as u32,
                super::SERVICE.as_ptr(),
                account.len() as u32,
                account.as_ptr(),
                length,
                data,
                item,
            )
        }
    }
    pub(super) fn read(account: &str) -> Result<Option<String>, String> {
        let keychain = default_keychain()?;
        let mut length = 0;
        let mut data = ptr::null_mut();
        let status = find(&keychain, account, &mut length, &mut data, ptr::null_mut());
        if status == -25300 {
            return Ok(None);
        }
        if status != 0 {
            return Err(error(status));
        }
        let value = if length == 0 {
            Ok(String::new())
        } else {
            String::from_utf8(
                unsafe { std::slice::from_raw_parts(data.cast::<u8>(), length as usize) }.to_vec(),
            )
            .map_err(|_| "vault_operation_failed".to_string())
        };
        let freed = unsafe { SecKeychainItemFreeContent(ptr::null_mut(), data) };
        if freed != 0 {
            return Err(error(freed));
        }
        value.map(Some)
    }
    pub(super) fn write(account: &str, secret: &str) -> Result<(), String> {
        let length =
            u32::try_from(secret.len()).map_err(|_| "vault_operation_failed".to_string())?;
        let keychain = default_keychain()?;
        let mut item = ptr::null_mut();
        let status = find(
            &keychain,
            account,
            ptr::null_mut(),
            ptr::null_mut(),
            &mut item,
        );
        let status = if status == -25300 {
            unsafe {
                SecKeychainAddGenericPassword(
                    keychain.0,
                    super::SERVICE.len() as u32,
                    super::SERVICE.as_ptr(),
                    account.len() as u32,
                    account.as_ptr(),
                    length,
                    secret.as_ptr(),
                    ptr::null_mut(),
                )
            }
        } else if status == 0 {
            let item = OwnedRef(item);
            unsafe {
                SecKeychainItemModifyAttributesAndData(
                    item.0,
                    ptr::null_mut(),
                    length,
                    secret.as_ptr(),
                )
            }
        } else {
            return Err(error(status));
        };
        if status == 0 {
            Ok(())
        } else {
            Err(error(status))
        }
    }
    pub(super) fn delete(account: &str) -> Result<(), String> {
        let keychain = default_keychain()?;
        let mut item = ptr::null_mut();
        let status = find(
            &keychain,
            account,
            ptr::null_mut(),
            ptr::null_mut(),
            &mut item,
        );
        if status == -25300 {
            return Ok(());
        }
        if status != 0 {
            return Err(error(status));
        }
        let item = OwnedRef(item);
        let status = unsafe { SecKeychainItemDelete(item.0) };
        if status == 0 || status == -25300 {
            Ok(())
        } else {
            Err(error(status))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(target_os = "macos")]
    #[test]
    fn authorization_status_codes_are_distinct() {
        assert_eq!(macos::error(-128), "storage_authorization_cancelled");
        assert_eq!(macos::error(-25293), "storage_access_denied");
        assert_eq!(macos::error(-25308), "storage_interaction_required");
        assert_eq!(macos::error(-25291), "system_vault_unavailable");
    }
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
