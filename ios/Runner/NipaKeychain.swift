import Flutter
import Foundation
import Security

/// The secret store of an iPad: the Keychain, readable after the first unlock,
/// never restored to another device from a backup and never synchronized to
/// iCloud (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, no
/// `kSecAttrSynchronizable`). That is what keeps two iPads from ever sharing
/// one Mesh identity.
final class NipaKeychain {
  private static let service = "com.aimessoft.nipaplay.vault"
  private static let queue = DispatchQueue(
    label: "com.aimessoft.nipaplay.keychain", qos: .userInitiated)

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "nipaplay/keychain", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard
        let args = call.arguments as? [String: Any],
        let namespace = args["namespace"] as? String,
        let key = args["key"] as? String,
        !namespace.isEmpty, !key.isEmpty
      else {
        result(FlutterError(code: "invalid_reference", message: nil, details: nil))
        return
      }
      let account = "\(namespace)\u{1F}\(key)"
      let secret = args["secret"] as? String
      queue.async {
        let outcome: Any?
        switch call.method {
        case "read":
          outcome = read(account)
        case "write":
          guard let secret = secret else {
            outcome = FlutterError(code: "invalid_reference", message: nil, details: nil)
            break
          }
          outcome = write(account, secret)
        case "delete":
          outcome = delete(account)
        default:
          outcome = FlutterMethodNotImplemented
        }
        DispatchQueue.main.async { result(outcome) }
      }
    }
  }

  private static func base(_ account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false,
    ]
  }

  private static func failure(_ status: OSStatus) -> FlutterError {
    NSLog("[NipaKeychain] OSStatus \(status)")
    let code: String
    switch status {
    case errSecInteractionNotAllowed: code = "storage_interaction_required"
    case errSecAuthFailed, errSecUserCanceled: code = "storage_authorization_cancelled"
    case errSecNotAvailable: code = "system_vault_unavailable"
    default: code = "vault_operation_failed"
    }
    return FlutterError(code: code, message: "OSStatus \(status)", details: nil)
  }

  private static func read(_ account: String) -> Any? {
    var query = base(account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else { return failure(status) }
    return String(data: data, encoding: .utf8)
  }

  private static func write(_ account: String, _ secret: String) -> Any? {
    let data = Data(secret.utf8)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(base(account) as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var add = base(account)
      for (name, value) in attributes { add[name] = value }
      status = SecItemAdd(add as CFDictionary, nil)
    }
    return status == errSecSuccess ? nil : failure(status)
  }

  private static func delete(_ account: String) -> Any? {
    let status = SecItemDelete(base(account) as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound ? nil : failure(status)
  }
}
