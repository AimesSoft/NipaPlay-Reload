pub fn vault_read(namespace: String, key: String) -> Result<Option<String>, String> {
    crate::vault::VaultService::read(&namespace, &key)
}

pub fn vault_write(namespace: String, key: String, secret: String) -> Result<(), String> {
    crate::vault::VaultService::write(&namespace, &key, &secret)
}

pub fn vault_delete(namespace: String, key: String) -> Result<(), String> {
    crate::vault::VaultService::delete(&namespace, &key)
}
