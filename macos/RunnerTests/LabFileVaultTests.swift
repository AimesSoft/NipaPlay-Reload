import Foundation
import Darwin

// Compile alongside SandboxMigration.swift as a standalone executable.
@main
enum LabFileVaultTests {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: message, code: 1) }
    }

    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("nipa-vault-test-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try! fm.removeItem(at: root) }
        let file = root.appendingPathComponent("credential-vault.json")
        func call(_ operation: String, _ namespace: String, _ key: String, _ secret: String? = nil) throws -> String? {
            var request: [String: Any] = ["operation": operation, "namespace": namespace, "key": key]
            if let secret { request["secret"] = secret }
            return try LabFileVault.operate(request, file: file)
        }
        try require(try call("read", "a", "bc") == nil, "missing entry")
        _ = try call("write", "a", "bc", "一次性测试")
        _ = try call("write", "ab", "c", "")
        try require(try call("read", "a", "bc") == "一次性测试", "namespace collision")
        try require(try call("read", "ab", "c") == "", "empty secret")
        _ = try call("write", "测试", "key", "unicode")
        _ = try call("write", "a", "bc", "updated")
        try require(try call("read", "测试", "key") == "unicode", "update lost another entry")
        let permissions = try fm.attributesOfItem(atPath: file.path)[.posixPermissions] as! NSNumber
        try require(permissions.intValue == 0o600, "file permissions")
        _ = try call("delete", "ab", "c")
        _ = try call("delete", "ab", "c")
        try require(try call("read", "a", "bc") == "updated", "delete lost another entry")
        print("PASS: reference boundaries, Unicode/empty secrets, update/delete preservation, 0600")

        let before = try Data(contentsOf: file)
        for request: [String: Any] in [
            ["operation": "write", "namespace": "", "key": "k", "secret": "bad"],
            ["operation": "write", "namespace": "n", "key": "\0", "secret": "bad"],
            ["operation": "write", "namespace": "n", "key": "k"],
            ["operation": "unknown", "namespace": "n", "key": "k"]
        ] {
            do {
                _ = try LabFileVault.operate(request, file: file)
                fatalError("invalid input accepted")
            } catch {}
        }
        try require(try Data(contentsOf: file) == before, "invalid input changed data")
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        do { _ = try call("write", "a", "bc", "bad"); fatalError("unsafe permissions accepted") } catch {}
        try require(try Data(contentsOf: file) == before, "unsafe permissions changed data")
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let target = root.appendingPathComponent("sentinel")
        try fm.moveItem(at: file, to: target)
        try fm.createSymbolicLink(at: file, withDestinationURL: target)
        do { _ = try call("read", "a", "bc"); fatalError("symlink accepted") } catch {}
        do { _ = try call("write", "a", "bc", "bad"); fatalError("symlink write accepted") } catch {}
        try require(try Data(contentsOf: target) == before, "symlink target changed")
        try fm.removeItem(at: file)
        try fm.linkItem(at: target, to: file)
        do { _ = try call("read", "a", "bc"); fatalError("hardlink accepted") } catch {}
        try fm.removeItem(at: file)
        try Data("broken JSON".utf8).write(to: file)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        do { _ = try call("write", "a", "bc", "bad"); fatalError("corrupt vault replaced") } catch {}
        try require(try Data(contentsOf: file) == Data("broken JSON".utf8), "corrupt data lost")
        try Data().write(to: file)
        do { _ = try call("write", "a", "bc", "bad"); fatalError("empty vault replaced") } catch {}
        try require(try Data(contentsOf: file).isEmpty, "empty corrupt file lost")
        print("PASS: invalid input/permissions, symlinks, hardlinks and corrupt data rejected without data loss")
        try require(try fm.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".vault-") }, "pending file leaked")
        print("PASS: no staging file remains")
    }
}
