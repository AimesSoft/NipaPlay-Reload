import Foundation
import CryptoKit
import Darwin
import ObjectiveC.runtime

@_silgen_name("sandbox_init")
private func installWriteSandbox(_ profile: UnsafePointer<CChar>, _ flags: UInt64,
                                 _ error: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
@_silgen_name("sandbox_free_error")
private func freeSandboxError(_ error: UnsafeMutablePointer<CChar>)

/// Installed before migration, plugins and the Flutter engine, inherited by children.
enum LabProfile {
    static private(set) var name: String?
    static private(set) var root: URL?
    static private(set) var writeSandbox = false
    static var active: Bool { name != nil }
    static func install() throws {
        unsetenv("NIPAPLAY_LAB_ROOT")
        #if DEBUG
        guard let value = ProcessInfo.processInfo.environment["NIPAPLAY_PROFILE"] else { return }
        guard value.range(of: "^[a-z0-9][a-z0-9_-]{0,63}$", options: .regularExpression) != nil else {
            throw NSError(domain: "LabProfile", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid NIPAPLAY_PROFILE"])
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NipaPlay/LabProfiles/\(value)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let canonical = directory.resolvingSymlinksInPath()
        guard canonical == directory.standardizedFileURL else {
            throw NSError(domain: "LabProfile", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Lab profile root must not be a symlink"])
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: canonical.path)
        for child in ["temp", "cache", "support", "data"] {
            try FileManager.default.createDirectory(at: canonical.appendingPathComponent(child), withIntermediateDirectories: true)
        }
        let defaults = try LabUserDefaults(file: canonical.appendingPathComponent("native-preferences.plist"))
        LabUserDefaults.profileDefaults = defaults
        let original = class_getClassMethod(UserDefaults.self, #selector(getter: UserDefaults.standard))!
        let replacement = class_getClassMethod(LabUserDefaults.self, #selector(LabUserDefaults.labStandard))!
        method_exchangeImplementations(original, replacement)
        setenv("TMPDIR", canonical.appendingPathComponent("temp").path + "/", 1)
        let quoted = canonical.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let keychains = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Keychains").path
            .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let policy = """
        (version 1)
        (allow default)
        (deny file-write*)
        (allow file-write* (subpath "\(quoted)"))
        (allow file-write-data (literal "/dev/null") (literal "/dev/tty"))
        (deny file-read* (subpath "\(keychains)"))
        (deny mach-lookup (global-name "com.apple.securityd") (global-name "com.apple.securityd.xpc") (global-name "com.apple.SecurityServer"))
        """
        var error: UnsafeMutablePointer<CChar>?
        let status = policy.withCString { installWriteSandbox($0, 0, &error) }
        if status != 0 {
            let message = error.map { String(cString: $0) } ?? "sandbox_init failed"
            if let error { freeSandboxError(error) }
            throw NSError(domain: "LabProfile", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
        name = value
        root = canonical
        writeSandbox = true
        setenv("NIPAPLAY_LAB_ROOT", canonical.path, 1)
        URLCache.shared = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0, diskPath: nil)
        print("[LabProfile] name=\(value) root=\(canonical.path) writeSandbox=true")
        #endif
    }
}

/// Disposable lab credentials stay in the profile; this backend never calls Security.
enum LabFileVault {
    private static let queue = DispatchQueue(label: "nipaplay.lab-vault")

    static func call(_ arguments: [String: Any], completion: @escaping (Any?, String?) -> Void) {
        let file = LabProfile.root!.appendingPathComponent("credential-vault.json")
        queue.async {
            do {
                let value = try operate(arguments, file: file)
                DispatchQueue.main.async { completion(value, nil) }
            } catch {
                let code = (error as? Failure)?.code ?? "vault_operation_failed"
                DispatchQueue.main.async { completion(nil, code) }
            }
        }
    }

    private struct Failure: Error {
        let code: String
    }

    static func operate(_ request: [String: Any], file: URL) throws -> String? {
        guard let operation = request["operation"] as? String,
              ["read", "write", "delete"].contains(operation),
              let namespace = request["namespace"] as? String, !namespace.isEmpty,
              let key = request["key"] as? String, !key.isEmpty,
              !namespace.contains("\0"), !key.contains("\0") else {
            throw Failure(code: "invalid_reference")
        }
        let account = "\(namespace.utf8.count):\(namespace)\(key)"
        var values = try read(file)
        switch operation {
        case "read":
            return values[account]
        case "write":
            guard let secret = request["secret"] as? String else {
                throw Failure(code: "invalid_reference")
            }
            values[account] = secret
        default:
            values.removeValue(forKey: account)
        }
        try save(values, file: file)
        return nil
    }

    private static func read(_ file: URL) throws -> [String: String] {
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        if descriptor < 0 {
            if errno == ENOENT { return [:] }
            throw Failure(code: "file_permissions_failed")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { handle.closeFile() }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_mode & 0o777 == 0o600, info.st_nlink == 1 else {
            throw Failure(code: "file_permissions_failed")
        }
        let data = try handle.readToEnd() ?? Data()
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private static func save(_ values: [String: String], file: URL) throws {
        let pending = file.deletingLastPathComponent().appendingPathComponent(".vault-\(UUID().uuidString)")
        let descriptor = open(pending.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw Failure(code: "file_permissions_failed") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            handle.closeFile()
            unlink(pending.path)
        }
        try handle.write(contentsOf: JSONEncoder().encode(values))
        try handle.synchronize()
        guard rename(pending.path, file.path) == 0 else {
            throw Failure(code: "vault_operation_failed")
        }
    }
}

func writeLabData(_ data: Data, to destination: URL) throws {
    let pending = destination.deletingLastPathComponent().appendingPathComponent(".lab-\(UUID().uuidString)")
    try data.write(to: pending)
    if rename(pending.path, destination.path) != 0 {
        let error = errno
        try FileManager.default.removeItem(at: pending)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(error))
    }
}

/// Native window/plugin preferences also stay inside the profile, without cfprefsd.
private class LabUserDefaults: UserDefaults {
    static var profileDefaults: LabUserDefaults!
    @objc class func labStandard() -> UserDefaults { profileDefaults }
    private let file: URL
    private var values: [String: Any]
    private let lock = NSRecursiveLock()
    init(file: URL) throws {
        self.file = file
        values = FileManager.default.fileExists(atPath: file.path)
            ? try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as! [String: Any] : [:]
        super.init(suiteName: "NipaPlay-Lab-InMemory")!
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    override func object(forKey key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }
    override func set(_ value: Any?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
        precondition(synchronize(), "Cannot save native lab preferences")
    }
    override func removeObject(forKey key: String) { set(nil, forKey: key) }
    override func dictionaryRepresentation() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return values
    }
    override func persistentDomain(forName name: String) -> [String: Any]? { dictionaryRepresentation() }
    override func setPersistentDomain(_ domain: [String: Any], forName name: String) {
        lock.lock(); defer { lock.unlock() }
        values = domain
        precondition(synchronize(), "Cannot save native lab preferences")
    }
    override func removePersistentDomain(forName name: String) { setPersistentDomain([:], forName: name) }
    override func synchronize() -> Bool {
        lock.lock(); defer { lock.unlock() }
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
            try writeLabData(data, to: file)
            return true
        } catch {
            NSLog("[LabProfile] Native preferences write failed: %@", error.localizedDescription)
            return false
        }
    }
}

@_silgen_name("sandbox_check")
private func processSandboxCheck(_ pid: pid_t, _ operation: UnsafePointer<CChar>?, _ filter: Int32) -> Int32

enum MacOSProcessEnvironment {
    // A nil operation queries whether this process is sandboxed, independent of build mode.
    static var isSandboxed: Bool { !LabProfile.active && processSandboxCheck(getpid(), nil, 0) != 0 }
}

private final class MigrationCopyDelegate: NSObject, FileManagerDelegate {
    func fileManager(_ fileManager: FileManager, shouldCopyItemAt srcURL: URL, to dstURL: URL) -> Bool {
        var info = stat()
        // External mpv IPC can leave a socket in Data/tmp after a crash. It has no persistent bytes.
        return lstat(srcURL.path, &info) != 0 || (info.st_mode & S_IFMT) != S_IFSOCK
    }
}

/// Runs before Flutter, UserDefaults consumers, databases and background workers start.
/// The container is never changed. Journal decisions survive process death.
final class SandboxMigration {
    struct Unit: Codable {
        let source: String
        let destination: String
        let digest: String
        let temporary: String
    }
    struct Archive: Codable {
        let destination: String
        let digest: String
        let temporary: String
        let copying: String
        let retired: String
        // cfprefsd owns the live plist; archive its bytes without moving that file.
        let copyOnly: Bool
    }
    struct Journal: Codable {
        var complete = false
        var preferencesPublished = false
        let snapshotDigest: String
        let preferencesDigest: String
        let ordinaryPreferencesDigest: String
        let units: [Unit]
        let archives: [Archive]
    }
    private let fm = FileManager()
    private let copyDelegate = MigrationCopyDelegate()
    private var omittedSockets = Set<String>()
    private let home: URL
    private let source: URL
    private let state: URL
    private let bundleID: String
    private let readPreferences: () throws -> [String: Any]
    private let writePreferences: ([String: Any]) throws -> Void
    // Test hook also covers the gap between atomic publication and completion recording.
    var checkpoint: (String) throws -> Void = { _ in }

    init(home: URL, source: URL, state: URL, bundleID: String,
         readPreferences: @escaping () throws -> [String: Any],
         writePreferences: @escaping ([String: Any]) throws -> Void) {
        self.home = home.standardizedFileURL.resolvingSymlinksInPath()
        self.source = source.standardizedFileURL.resolvingSymlinksInPath()
        self.state = state.standardizedFileURL.resolvingSymlinksInPath()
        self.bundleID = bundleID
        self.readPreferences = readPreferences
        self.writePreferences = writePreferences
        fm.delegate = copyDelegate
    }

    static func runBeforeEngine() throws {
        guard !MacOSProcessEnvironment.isSandboxed else { return }
        if LabProfile.active { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bundleID = Bundle.main.bundleIdentifier!
        let migration = SandboxMigration(
            home: home,
            source: home.appendingPathComponent("Library/Containers/\(bundleID)/Data"),
            state: home.appendingPathComponent("Library/Application Support/NipaPlay Sandbox Migration/\(bundleID)/v1"),
            bundleID: bundleID,
            readPreferences: { UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:] },
            writePreferences: { values in
                UserDefaults.standard.setPersistentDomain(values, forName: bundleID)
                guard UserDefaults.standard.synchronize() else {
                    throw failure("无法持久保存偏好设置")
                }
                let actual = UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]
                guard NSDictionary(dictionary: actual).isEqual(to: values) else {
                    throw failure("偏好设置校验失败")
                }
            })
        try migration.run()
    }

    func run() throws {
        try fm.createDirectory(at: state, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let lock = open(state.appendingPathComponent("lock").path, O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { throw Self.failure("无法打开迁移锁") }
        defer { close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { throw Self.failure("无法锁定迁移") }
        defer { flock(lock, LOCK_UN) }

        let journalURL = state.appendingPathComponent("journal.plist")
        let snapshot = state.appendingPathComponent("container-copy")
        var journal: Journal
        if try exists(journalURL) {
            journal = try PropertyListDecoder().decode(Journal.self, from: Data(contentsOf: journalURL))
            if journal.complete { return }
            guard try digest(snapshot) == journal.snapshotDigest else {
                throw Self.failure("迁移归档校验失败；原容器仍保留")
            }
        } else {
            // No journal means nothing has been published; an interrupted snapshot can be rebuilt.
            guard try exists(source) else { return }
            if try exists(snapshot) { try fm.removeItem(at: snapshot) }
            let sourceDigest = try digest(source)
            try fm.copyItem(at: source, to: snapshot)
            try checkpoint("snapshotCopied")
            guard try digest(snapshot) == sourceDigest, try digest(source) == sourceDigest else {
                throw Self.failure("复制期间容器数据发生变化；请关闭旧版本后重试")
            }
            let socketIndex = try PropertyListSerialization.data(fromPropertyList: omittedSockets.sorted(), format: .binary, options: 0)
            try socketIndex.write(to: state.appendingPathComponent("volatile-sockets.plist"), options: .atomic)
            let (units, archives) = try plan(snapshot: snapshot)
            let oldPlist = snapshot.appendingPathComponent("Library/Preferences/\(bundleID).plist")
            let preferences = try exists(oldPlist) ? Self.preferences(at: oldPlist) : [:]
            let preferencesURL = state.appendingPathComponent("preferences.plist")
            try Self.plist(preferences).write(to: preferencesURL, options: .atomic)
            let ordinaryPreferencesURL = state.appendingPathComponent("ordinary-preferences.plist")
            try Self.plist(readPreferences()).write(to: ordinaryPreferencesURL, options: .atomic)
            journal = Journal(snapshotDigest: sourceDigest,
                              preferencesDigest: try digest(preferencesURL),
                              ordinaryPreferencesDigest: try digest(ordinaryPreferencesURL),
                              units: units, archives: archives)
            try save(journal, to: journalURL)
            try checkpoint("planned")
        }

        guard try digest(state.appendingPathComponent("ordinary-preferences.plist")) == journal.ordinaryPreferencesDigest else {
            throw Self.failure("原偏好归档校验失败")
        }
        // Archive all ordinary groups (including SQLite sidecars absent from the container)
        // before publishing any container group. Each move is recoverable from the journal.
        for (index, archive) in journal.archives.enumerated() {
            try archiveOrdinary(archive, index: index)
        }
        try verifyRetiredSidecars(journal)
        for (index, unit) in journal.units.enumerated() {
            let target = home.appendingPathComponent(unit.destination)
            let input = state.appendingPathComponent(unit.source)
            guard try digest(input) == unit.digest else { throw Self.failure("迁移输入校验失败") }
            if try exists(target) {
                if try isDirectory(target), try children(target).isEmpty {
                    // Only an empty placeholder can be removed. rmdir fails if another process adds data.
                    guard rmdir(target.path) == 0 else { throw Self.failure("迁移目标目录已改变") }
                } else {
                    // A rename can have succeeded immediately before process death.
                    guard try digest(target) == unit.digest else {
                        throw Self.failure("迁移目标已改变，未覆盖现有数据：\(unit.destination)")
                    }
                    continue
                }
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = home.appendingPathComponent(unit.temporary)
            if try exists(temporary) { try fm.removeItem(at: temporary) }
            try fm.copyItem(at: input, to: temporary)
            try checkpoint("unitCopied:\(index)")
            guard try digest(temporary) == unit.digest else { throw Self.failure("迁移副本校验失败") }
            // rename is atomic on the destination filesystem; never replace a pre-existing target.
            guard renamex_np(temporary.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
                throw Self.failure("无法发布迁移数据：\(unit.destination)")
            }
            try checkpoint("unitPublished:\(index)")
        }
        let preferencesURL = state.appendingPathComponent("preferences.plist")
        guard try digest(preferencesURL) == journal.preferencesDigest else {
            throw Self.failure("容器偏好计划校验失败")
        }
        if !journal.preferencesPublished {
            let preferences = try Self.preferences(at: preferencesURL)
            try writePreferences(preferences)
            guard NSDictionary(dictionary: try readPreferences()).isEqual(to: preferences) else {
                throw Self.failure("偏好设置校验失败")
            }
            try checkpoint("preferencesWritten")
            journal.preferencesPublished = true
            try save(journal, to: journalURL)
            try checkpoint("preferencesPublished")
        }
        for unit in journal.units {
            guard try digest(home.appendingPathComponent(unit.destination)) == unit.digest else {
                throw Self.failure("迁移完成校验失败")
            }
        }
        for archive in journal.archives {
            guard try digest(state.appendingPathComponent("ordinary-archive/" + archive.destination)) == archive.digest else {
                throw Self.failure("原数据归档完成校验失败")
            }
        }
        try verifyRetiredSidecars(journal)
        var completed = journal
        completed.complete = true
        try save(completed, to: journalURL)
    }

    private func verifyRetiredSidecars(_ journal: Journal) throws {
        let publishedPaths = Set(journal.units.map { $0.destination })
        for archive in journal.archives where !archive.copyOnly && !publishedPaths.contains(archive.destination) {
            guard try !exists(home.appendingPathComponent(archive.destination)) else {
                throw Self.failure("已归档的旧数据库附属文件重新出现：\(archive.destination)")
            }
        }
    }

    private func archiveOrdinary(_ archive: Archive, index: Int) throws {
        let target = home.appendingPathComponent(archive.destination)
        let saved = state.appendingPathComponent("ordinary-archive/" + archive.destination)
        let temporary = home.appendingPathComponent(archive.temporary)
        let retired = home.appendingPathComponent(archive.retired)
        if try exists(saved) {
            guard try digest(saved) == archive.digest else { throw Self.failure("原数据归档校验失败") }
        } else {
            if try !archive.copyOnly && !exists(temporary) {
                guard try exists(target), try digest(target) == archive.digest else {
                    throw Self.failure("待归档的普通数据已改变：\(archive.destination)")
                }
                // Move out of the live path atomically on its filesystem. A verified copy then
                // reaches the private archive even when Documents and Library are on different volumes.
                guard renamex_np(target.path, temporary.path, UInt32(RENAME_EXCL)) == 0 else {
                    throw Self.failure("无法暂存原数据：\(archive.destination)")
                }
                try checkpoint("ordinaryMoved:\(index)")
            }
            let input = archive.copyOnly ? target : temporary
            guard try digest(input) == archive.digest else { throw Self.failure("原数据暂存校验失败") }
            try fm.createDirectory(at: saved.deletingLastPathComponent(), withIntermediateDirectories: true)
            let copying = state.appendingPathComponent(archive.copying)
            if try exists(copying) { try fm.removeItem(at: copying) }
            try fm.copyItem(at: input, to: copying)
            try checkpoint("ordinaryCopied:\(index)")
            guard try digest(copying) == archive.digest, try digest(input) == archive.digest else {
                throw Self.failure("复制期间原数据发生变化")
            }
            guard renamex_np(copying.path, saved.path, UInt32(RENAME_EXCL)) == 0 else {
                throw Self.failure("无法发布原数据归档")
            }
            try checkpoint("ordinaryArchived:\(index)")
        }
        if try !archive.copyOnly && exists(temporary) {
            guard try digest(temporary) == archive.digest else { throw Self.failure("原数据暂存已改变") }
            // Record cleanup by an atomic rename before recursive deletion. If SIGKILL interrupts
            // deletion, recovery can finish deleting a partial duplicate without rejecting its digest.
            guard renamex_np(temporary.path, retired.path, UInt32(RENAME_EXCL)) == 0 else {
                throw Self.failure("无法整理已归档的原数据暂存")
            }
            try checkpoint("ordinaryRetired:\(index)")
        }
        if try !archive.copyOnly && exists(retired) {
            // The complete verified archive is retained; only its redundant staging copy is removed.
            try fm.removeItem(at: retired)
        }
    }

    private func plan(snapshot: URL) throws -> ([Unit], [Archive]) {
        var units: [Unit] = []
        var archives: [Archive] = []
        var archivedPaths = Set<String>()
        func archive(_ destination: String, copyOnly: Bool = false) throws {
            let target = home.appendingPathComponent(destination)
            guard try exists(target), archivedPaths.insert(destination).inserted else { return }
            if try isDirectory(target), try children(target).isEmpty { return }
            archives.append(Archive(destination: destination, digest: try digest(target),
                                    temporary: destination + ".nipa-archive-" + UUID().uuidString,
                                    copying: "ordinary-copy-" + UUID().uuidString,
                                    retired: destination + ".nipa-retired-" + UUID().uuidString,
                                    copyOnly: copyOnly))
        }
        func add(_ input: URL, _ destination: String) throws {
            let family = sqliteFamily(input.lastPathComponent)
            if try family.count > 1 && !isDirectory(input) {
                for member in family {
                    let relative = (destination as NSString).deletingLastPathComponent + "/" + member
                    try archive(relative)
                }
            } else { try archive(destination) }
            let canonicalInput = input.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(input.lastPathComponent)
            units.append(Unit(source: String(canonicalInput.path.dropFirst(state.path.count + 1)),
                              destination: destination, digest: try digest(input),
                              temporary: destination + ".nipa-migration-" + UUID().uuidString))
        }
        let documents = snapshot.appendingPathComponent("Documents")
        if try isDirectory(documents) {
            // Current storage is Documents/nipaplay. Older Classic versions used Documents itself.
            let active = state.appendingPathComponent("active-documents")
            if try exists(active) { try fm.removeItem(at: active) }
            let current = documents.appendingPathComponent("nipaplay")
            if try isDirectory(current) { try fm.copyItem(at: current, to: active) }
            else { try fm.createDirectory(at: active, withIntermediateDirectories: true) }
            for entry in try children(documents) where entry.lastPathComponent != "nipaplay" {
                let target = active.appendingPathComponent(entry.lastPathComponent)
                // Keep a database and its sidecars from the same generation.
                let currentFamily = sqliteFamily(entry.lastPathComponent)
                let hasCurrentFamily = try currentFamily.contains { try exists(current.appendingPathComponent($0)) }
                if try !exists(target) && !hasCurrentFamily {
                    try fm.copyItem(at: entry, to: target)
                }
            }
            try add(active, "Documents/nipaplay")
        }
        let library = snapshot.appendingPathComponent("Library")
        if try isDirectory(library) {
            for category in try children(library) {
                // Preferences go through cfprefsd; Keychain stays with the OS and its existing service identity.
                if ["Preferences", "Keychains"].contains(category.lastPathComponent) { continue }
                // Containers have links to shared system directories. Archive those links, never traverse them.
                guard try isDirectory(category) else { continue }
                for entry in try children(category) {
                    // A container mirrors shared user data (AddressBook, iCloud, Images/People,
                    // shared caches) as links or private copies. Outside the sandbox those names
                    // belong to the system and other apps; on 2026-10-11 publishing them replaced the
                    // user's real Contacts and iCloud directories. Only NipaPlay's own entries move.
                    guard try !isSymbolicLink(entry), ownedByApp(entry.lastPathComponent) else { continue }
                    let relative = "Library/\(category.lastPathComponent)/\(entry.lastPathComponent)"
                    try add(entry, relative)
                }
            }
        }
        // Data/tmp and every other container entry remain in the verified, private archive.
        // path_provider's macOS getTemporaryDirectory actually uses Library/Caches, covered above.
        try archive("Library/Preferences/\(bundleID).plist", copyOnly: true)
        return (units, archives)
    }

    private func sqliteFamily(_ name: String) -> [String] {
        let suffix = ["-wal", "-shm", "-journal"].first { name.hasSuffix($0) }
        let candidate = suffix.map { String(name.dropLast($0.count)) } ?? name
        guard ["db", "sqlite", "sqlite3"].contains(URL(fileURLWithPath: candidate).pathExtension) else { return [name] }
        return [candidate, candidate + "-wal", candidate + "-shm", candidate + "-journal"]
    }

    private func ownedByApp(_ name: String) -> Bool {
        name == bundleID || name.hasPrefix(bundleID + ".") || name.lowercased().contains("nipaplay")
    }
    private func isSymbolicLink(_ url: URL) throws -> Bool {
        guard try exists(url) else { return false }
        return try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeSymbolicLink
    }
    private func exists(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 { return true }
        if errno == ENOENT { return false }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    private func isDirectory(_ url: URL) throws -> Bool {
        guard try exists(url) else { return false }
        return try fm.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory
    }
    private func children(_ url: URL) throws -> [URL] {
        try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    private func digest(_ root: URL) throws -> String {
        var hash = SHA256()
        func token(_ value: String) { hash.update(data: Data((value + "\0").utf8)) }
        func visit(_ url: URL, _ relative: String) throws {
            let attributes = try fm.attributesOfItem(atPath: url.path)
            let type = attributes[.type] as! FileAttributeType
            if type == .typeSocket {
                if root == source { omittedSockets.insert(relative) }
                return
            }
            token(relative)
            token(type.rawValue)
            if type == .typeDirectory {
                for child in try children(url) { try visit(child, relative + "/" + child.lastPathComponent) }
            } else if type == .typeSymbolicLink {
                token(try fm.destinationOfSymbolicLink(atPath: url.path))
            } else if type == .typeRegular {
                token(String((attributes[.size] as! NSNumber).uint64Value))
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
            } else {
                throw Self.failure("容器中存在无法复制的文件类型：\(relative)")
            }
        }
        try visit(root, "")
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func save(_ journal: Journal, to url: URL) throws {
        try PropertyListEncoder().encode(journal).write(to: url, options: .atomic)
    }
    private static func plist(_ values: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
    }
    private static func preferences(at url: URL) throws -> [String: Any] {
        guard let values = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any] else {
            throw failure("偏好设置不是有效的 plist 字典")
        }
        return values
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "NipaPlaySandboxMigration", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
