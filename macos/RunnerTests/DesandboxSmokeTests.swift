// Standalone native smoke tests use temporary media and a temporary Keychain, never Runner's data.
import Foundation
import Security
import Darwin

private func require(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: "NipaPlaySmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

@main
enum DesandboxSmokeTests {
    static func main() throws {
        try require(!MacOSProcessEnvironment.isSandboxed, "smoke process must be unsandboxed")
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("nipaplay-native-smoke-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        let bookmark = try root.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        var stale = false
        let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        try require(resolved.resolvingSymlinksInPath() == root.resolvingSymlinksInPath(), "bookmark path changed")
        try Data("media-access".utf8).write(to: resolved.appendingPathComponent("access.txt"))
        print("PASS: ordinary bookmark resolves and grants normal folder read/write without security scope")

        try keychain(root)
        try loopbackNetwork()
        try nativeLibraries(root)
    }

    private static func keychain(_ root: URL) throws {
        var keychain: SecKeychain?
        let password = "isolated-test-keychain"
        let status = root.appendingPathComponent("test.keychain-db").path.withCString { location in
            password.withCString { bytes in
                SecKeychainCreate(location, UInt32(password.utf8.count), bytes, false, nil, &keychain)
            }
        }
        try require(status == errSecSuccess, "temporary Keychain create failed: \(status)")
        let store = keychain!
        defer { SecKeychainDelete(store) }
        let service = "com.nipaplay.credential-vault.v1"
        let account = "isolated-smoke-" + UUID().uuidString
        let secret = "temporary-fixture-value"
        let add = service.withCString { s in
            account.withCString { a in
                secret.withCString { value in
                    SecKeychainAddGenericPassword(store, UInt32(service.utf8.count), s,
                                                  UInt32(account.utf8.count), a,
                                                  UInt32(secret.utf8.count), value, nil)
                }
            }
        }
        try require(add == errSecSuccess, "temporary vault write failed: \(add)")
        var length: UInt32 = 0
        var data: UnsafeMutableRawPointer?
        let read = service.withCString { s in
            account.withCString { a in
                SecKeychainFindGenericPassword(store, UInt32(service.utf8.count), s,
                                               UInt32(account.utf8.count), a, &length, &data, nil)
            }
        }
        try require(read == errSecSuccess, "temporary vault read failed: \(read)")
        defer { SecKeychainItemFreeContent(nil, data) }
        try require(Data(bytes: data!, count: Int(length)) == Data(secret.utf8), "temporary vault value changed")
        print("PASS: isolated Keychain read/write with com.nipaplay.credential-vault.v1")
    }

    private static func loopbackNetwork() throws {
        let server = socket(AF_INET, SOCK_STREAM, 0)
        try require(server >= 0, "server socket failed")
        defer { close(server) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        try require(bound == 0 && listen(server, 1) == 0, "loopback server bind failed")
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(server, $0, &size) }
        }
        try require(named == 0, "loopback port lookup failed")
        let client = socket(AF_INET, SOCK_STREAM, 0)
        try require(client >= 0, "client socket failed")
        defer { close(client) }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(client, $0, size) }
        }
        try require(connected == 0, "loopback client connect failed")
        let accepted = accept(server, nil, nil)
        try require(accepted >= 0, "loopback accept failed")
        defer { close(accepted) }
        let sent = "network-fixture".withCString { send(client, $0, 15, 0) }
        var received = [UInt8](repeating: 0, count: 15)
        try require(sent == 15 && recv(accepted, &received, received.count, 0) == 15, "loopback transfer failed")
        print("PASS: loopback network client and server without sandbox network entitlements")
    }

    private static func nativeLibraries(_ root: URL) throws {
        let frameworks = URL(fileURLWithPath: CommandLine.arguments[1])
        for library in ["rust_lib_nipaplay.framework/rust_lib_nipaplay", "libnipaplay_native.dylib", "mdk.framework/mdk"] {
            guard let handle = dlopen(frameworks.appendingPathComponent(library).path, RTLD_NOW | RTLD_LOCAL) else {
                throw NSError(domain: "dlopen", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: dlerror())])
            }
            dlclose(handle)
            print("PASS: native library loads: \(library)")
        }
        guard let library = dlopen(frameworks.appendingPathComponent("Mpv.framework/Mpv").path, RTLD_NOW | RTLD_LOCAL) else {
            throw NSError(domain: "dlopen", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: dlerror())])
        }
        defer { dlclose(library) }
        typealias Create = @convention(c) () -> OpaquePointer?
        typealias SetOption = @convention(c) (OpaquePointer, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
        typealias Initialize = @convention(c) (OpaquePointer) -> Int32
        typealias Command = @convention(c) (OpaquePointer, UnsafePointer<UnsafePointer<CChar>?>) -> Int32
        typealias Destroy = @convention(c) (OpaquePointer) -> Void
        typealias GetProperty = @convention(c) (OpaquePointer, UnsafePointer<CChar>, Int32, UnsafeMutableRawPointer) -> Int32
        let create = unsafeBitCast(dlsym(library, "mpv_create")!, to: Create.self)
        let option = unsafeBitCast(dlsym(library, "mpv_set_option_string")!, to: SetOption.self)
        let initialize = unsafeBitCast(dlsym(library, "mpv_initialize")!, to: Initialize.self)
        let command = unsafeBitCast(dlsym(library, "mpv_command")!, to: Command.self)
        let property = unsafeBitCast(dlsym(library, "mpv_get_property")!, to: GetProperty.self)
        let destroy = unsafeBitCast(dlsym(library, "mpv_terminate_destroy")!, to: Destroy.self)
        let player = create()!
        defer { destroy(player) }
        for (key, value) in [("vo", "null"), ("ao", "null"), ("config", "no"), ("idle", "yes"), ("pause", "yes")] {
            try require(option(player, key, value) == 0, "mpv option failed")
        }
        try require(initialize(player) == 0, "mpv initialization failed")
        let image = root.appendingPathComponent("video-fixture.ppm")
        var bytes = Data("P6\n16 16\n255\n".utf8)
        bytes.append(Data(repeating: 128, count: 16 * 16 * 3))
        try bytes.write(to: image)
        let strings: [UnsafeMutablePointer<CChar>] = ["loadfile", image.path].map { value in
            value.withCString { strdup($0)! }
        }
        defer { strings.forEach { free($0) } }
        let arguments: [UnsafePointer<CChar>?] = strings.map { UnsafePointer($0) } + [nil]
        try require(arguments.withUnsafeBufferPointer { command(player, $0.baseAddress!) } == 0, "mpv loadfile failed")
        // Wait only for this local fixture's decoder, with a bounded timeout.
        let deadline = Date().addingTimeInterval(5)
        var width: Int64 = 0
        while Date() < deadline {
            if property(player, "width", 4, &width) == 0 && width == 16 { break }
            usleep(10_000)
        }
        try require(width == 16, "mpv did not decode the local video fixture")
        print("PASS: bundled mpv loads, initializes and decodes a local 16x16 video frame")
    }
}
