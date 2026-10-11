// Standalone native tests: compile with SandboxMigration.swift; never launch Runner.
import Foundation
import Darwin

private let bundleID = "com.aimessoft.nipaplay"
private let fm = FileManager.default
private enum Interrupted: Error { case simulatedKill }

private final class Fixture {
    let root: URL
    let home: URL
    let source: URL
    let state: URL
    var preferences: [String: Any] = [:]

    init(root suppliedRoot: URL? = nil) throws {
        root = suppliedRoot ?? fm.temporaryDirectory.appendingPathComponent("nipaplay-migration-test-" + UUID().uuidString)
        home = root.appendingPathComponent("home")
        source = root.appendingPathComponent("container/Data")
        state = root.appendingPathComponent("migration")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let plist = home.appendingPathComponent("Library/Preferences/\(bundleID).plist")
        if fm.fileExists(atPath: plist.path) {
            preferences = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
        }
    }
    func clean() throws { try fm.removeItem(at: root) }
    func migrator() -> SandboxMigration {
        SandboxMigration(home: home, source: source, state: state, bundleID: bundleID,
                         readPreferences: {
                             // A killed worker may have published the domain in a separate process.
                             let plist = self.home.appendingPathComponent("Library/Preferences/\(bundleID).plist")
                             if fm.fileExists(atPath: plist.path) {
                                 self.preferences = try PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as! [String: Any]
                             }
                             return self.preferences
                         },
                         writePreferences: {
                             self.preferences = $0
                             try self.writeOrdinaryPreferences()
                         })
    }
    func write(_ relative: String, _ value: String, in directory: URL? = nil) throws {
        let target = (directory ?? source).appendingPathComponent(relative)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(value.utf8).write(to: target)
    }
    func text(_ relative: String, in directory: URL? = nil) throws -> String {
        try String(contentsOf: (directory ?? home).appendingPathComponent(relative), encoding: .utf8)
    }
    func seedOrdinary() throws {
        try write("Documents/nipaplay/watch_history.db", "ordinary-history", in: home)
        try write("Documents/nipaplay/watch_history.db-wal", "ordinary-wal", in: home)
        try write("Documents/nipaplay/watch_history.db-shm", "ordinary-shm", in: home)
        try write("Documents/nipaplay/next/next.db", "ordinary-next", in: home)
        try write("Documents/nipaplay/ordinary-only.txt", "ordinary-only", in: home)
        try fm.createDirectory(at: home.appendingPathComponent("Documents/nipaplay/empty"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: home.appendingPathComponent("Documents/nipaplay/broken-link").path,
                                 withDestinationPath: "/missing/ordinary-media")
        try write("Library/Application Support/\(bundleID)/old-font.ttf", "ordinary-font", in: home)
        try write("Library/Application Support/NipaPlay/torrent_session/old-session", "ordinary-session", in: home)
        try write("Library/Caches/\(bundleID)/old-image", "ordinary-cache", in: home)
        preferences = ["flutter.locale": "en", "ordinary-only": 17]
        try writeOrdinaryPreferences()
    }
    func writeOrdinaryPreferences() throws {
        let url = home.appendingPathComponent("Library/Preferences/\(bundleID).plist")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: preferences, format: .binary, options: 0).write(to: url)
    }
    func reloadPreferences() throws {
        let url = home.appendingPathComponent("Library/Preferences/\(bundleID).plist")
        if fm.fileExists(atPath: url.path) {
            preferences = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as! [String: Any]
        }
    }
    func expectSameTree(_ original: URL, _ archived: URL) throws {
        let type = try fm.attributesOfItem(atPath: original.path)[.type] as! FileAttributeType
        try expect(fm.attributesOfItem(atPath: archived.path)[.type] as? FileAttributeType == type, "archive type changed")
        if type == .typeDirectory {
            let names = try fm.contentsOfDirectory(atPath: original.path).sorted()
            try expect(fm.contentsOfDirectory(atPath: archived.path).sorted() == names, "archive entries changed")
            for name in names { try expectSameTree(original.appendingPathComponent(name), archived.appendingPathComponent(name)) }
        } else if type == .typeSymbolicLink {
            try expect(fm.destinationOfSymbolicLink(atPath: original.path) == fm.destinationOfSymbolicLink(atPath: archived.path), "archive link changed")
        } else {
            try expect(Data(contentsOf: original) == Data(contentsOf: archived), "archive bytes changed: \(archived.path)")
        }
    }
    func checkOrdinaryArchived() throws {
        try expect(text("ordinary-archive/Documents/nipaplay/watch_history.db", in: state) == "ordinary-history", "ordinary history archive missing")
        try expect(text("ordinary-archive/Documents/nipaplay/watch_history.db-wal", in: state) == "ordinary-wal", "ordinary WAL archive missing")
        try expect(text("ordinary-archive/Documents/nipaplay/next/next.db", in: state) == "ordinary-next", "ordinary Next archive missing")
        try expect(preferences["ordinary-only"] == nil, "ordinary-only preference survived")
    }
    func seed() throws {
        try write("Documents/nipaplay/watch_history.db", "container-history")
        try write("Documents/nipaplay/watch_history.db-wal", "matching-wal")
        try write("Documents/nipaplay/next/next.db", "next-facts")
        try write("Documents/nipaplay/next/workspace/tool.py", "user-tool")
        try write("Documents/legacy-only.json", "legacy")
        try write("Library/Application Support/\(bundleID)/fonts/font.ttf", "font")
        try write("Library/Application Support/NipaPlay/torrent_session/session.json", "torrent-resume")
        try write("Library/Caches/\(bundleID)/image", "cache")
        try write("Library/Caches/temporary-image", "temporary")
        try write("tmp/download.partial", "partial-download")
        try write("Library/Keychains/private.db", "archive-only-keychain")
        let preferencesURL = source.appendingPathComponent("Library/Preferences/\(bundleID).plist")
        try fm.createDirectory(at: preferencesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old: [String: Any] = ["flutter.locale": "zh", "flutter.security_bookmark_/media": Data([1, 2, 3]),
                                  "flutter.labs_enable_agent_endpoint": true]
        try PropertyListSerialization.data(fromPropertyList: old, format: .binary, options: 0).write(to: preferencesURL)
    }
    func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    func checkImported() throws {
        try expect(text("Documents/nipaplay/watch_history.db") == "container-history", "history missing")
        try expect(text("Documents/nipaplay/watch_history.db-wal") == "matching-wal", "WAL missing")
        try expect(text("Documents/nipaplay/next/next.db") == "next-facts", "Next missing")
        try expect(text("Documents/nipaplay/next/workspace/tool.py") == "user-tool", "workspace missing")
        try expect(text("Documents/nipaplay/legacy-only.json") == "legacy", "legacy documents missing")
        try expect(text("Library/Application Support/\(bundleID)/fonts/font.ttf") == "font", "support missing")
        try expect(text("Library/Application Support/NipaPlay/torrent_session/session.json") == "torrent-resume", "Rust torrent session missing")
        try expect(text("container-copy/Library/Caches/temporary-image", in: state) == "temporary", "shared cache root not archived")
        try expect((try? text("Library/Caches/temporary-image")) != "temporary", "shared cache root published")
        try expect(text("container-copy/tmp/download.partial", in: state) == "partial-download", "tmp archive missing")
        try expect(text("container-copy/Library/Keychains/private.db", in: state) == "archive-only-keychain", "Keychain archive missing")
        try expect(preferences["flutter.locale"] as? String == "zh", "preferences missing")
        try expect(preferences["flutter.security_bookmark_/media"] as? Data == Data([1, 2, 3]), "bookmark changed")
        try expect(text("Documents/nipaplay/watch_history.db", in: source) == "container-history", "container changed")
        let journal = try PropertyListSerialization.propertyList(from: Data(contentsOf: state.appendingPathComponent("journal.plist")), format: nil) as! [String: Any]
        try expect(journal["complete"] as? Bool == true, "migration not complete")
    }
}

@main
enum SandboxMigrationTests {
    static func main() throws {
        setbuf(stdout, nil)
        if CommandLine.arguments.contains("--probe-sandbox") {
            print("sandboxed=\(MacOSProcessEnvironment.isSandboxed)")
            return
        }
        if CommandLine.arguments.contains("--maintainer-fixture") {
            let f = try Fixture()
            defer { try? f.clean() }
            try f.seed()
            for (name, bytes) in [("cache", 10 * 1024 * 1024), ("compressed_images", 12 * 1024 * 1024), ("logs", 1024 * 1024)] {
                let url = f.home.appendingPathComponent("Documents/nipaplay/\(name)/old-data")
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(repeating: 0x6a, count: bytes).write(to: url)
            }
            let ordinaryDocuments = f.home.appendingPathComponent("Documents/nipaplay")
            try fm.setAttributes([.modificationDate: ISO8601DateFormatter().date(from: "2026-07-23T00:00:00Z")!], ofItemAtPath: ordinaryDocuments.path)
            f.preferences = ["flutter.locale": "en", "ordinary-only": "June setting", "old-cache": Data(repeating: 0x28, count: 200 * 1024)]
            try f.writeOrdinaryPreferences()
            let ordinaryPlist = f.home.appendingPathComponent("Library/Preferences/\(bundleID).plist")
            try fm.setAttributes([.modificationDate: ISO8601DateFormatter().date(from: "2026-06-28T00:00:00Z")!], ofItemAtPath: ordinaryPlist.path)
            try fm.createDirectory(at: f.home.appendingPathComponent("Library/Application Support/NipaPlay"), withIntermediateDirectories: true)
            let before = f.root.appendingPathComponent("ordinary-before")
            try fm.copyItem(at: f.home, to: before)
            let cacheBytes = try ["cache", "compressed_images", "logs"].reduce(0) {
                $0 + (try Data(contentsOf: ordinaryDocuments.appendingPathComponent("\($1)/old-data"))).count
            }
            let hasHistory = fm.fileExists(atPath: ordinaryDocuments.appendingPathComponent("watch_history.db").path)
            let hasNext = fm.fileExists(atPath: ordinaryDocuments.appendingPathComponent("next").path)
            try f.expect(!hasHistory && !hasNext, "ordinary fixture contains history or Next")
            let supportEntries = try fm.contentsOfDirectory(atPath: f.home.appendingPathComponent("Library/Application Support/NipaPlay").path).count
            try f.expect(supportEntries == 0, "support fixture is not empty")
            print("Fixture: \(f.root.path) (temporary; removed after verification)")
            print("Before: ordinary Documents/nipaplay = \(cacheBytes) bytes of cache/compressed_images/logs; mtime=2026-07-23; history=\(hasHistory); next=\(hasNext)")
            print("Before: ordinary plist = \((try Data(contentsOf: ordinaryPlist)).count) bytes; mtime=2026-06-28; locale=en; ordinary-only=June setting")
            print("Before: ordinary Application Support/NipaPlay entries=\(supportEntries); container has Classic, Next, support, bookmarks and preferences")
            try f.migrator().run()
            try f.checkImported()
            try f.expect(f.preferences["ordinary-only"] == nil && f.preferences["old-cache"] == nil, "old preference keys retained")
            let activePreferences = try PropertyListSerialization.propertyList(from: Data(contentsOf: ordinaryPlist), format: nil) as! [String: Any]
            try f.expect(NSDictionary(dictionary: activePreferences).isEqual(to: f.preferences), "active plist domain differs")
            try f.expectSameTree(before.appendingPathComponent("Documents/nipaplay"), f.state.appendingPathComponent("ordinary-archive/Documents/nipaplay"))
            try f.expectSameTree(before.appendingPathComponent("Library/Preferences/\(bundleID).plist"), f.state.appendingPathComponent("ordinary-archive/Library/Preferences/\(bundleID).plist"))
            print("After: active history=\(try f.text("Documents/nipaplay/watch_history.db")); WAL=\(try f.text("Documents/nipaplay/watch_history.db-wal")); Next=\(try f.text("Documents/nipaplay/next/next.db")); workspace=\(try f.text("Documents/nipaplay/next/workspace/tool.py"))")
            let bookmark = (f.preferences["flutter.security_bookmark_/media"] as! Data).map { String(format: "%02x", $0) }.joined()
            print("After: active locale=\(f.preferences["flutter.locale"] as! String); bookmark bytes=\(bookmark); ordinary-only absent; old-cache absent")
            print("Archive: ordinary cache tree (\(cacheBytes) bytes) and original plist match every entry/type/byte; no merge into active Documents")
            try f.expect(!fm.fileExists(atPath: f.home.appendingPathComponent("Documents/nipaplay/cache").path), "old cache merged")
            print("After: torrent_session=\(try f.text("Library/Application Support/NipaPlay/torrent_session/session.json")); empty support placeholder replaced; container retained; journal complete=true")
            print("PASS: maintainer Mac fixture uses container data and archives stale ordinary data intact")
            return
        }
        if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--kill-worker" {
            let fixture = try Fixture(root: URL(fileURLWithPath: CommandLine.arguments[2]))
            let migration = fixture.migrator()
            migration.checkpoint = { if $0 == CommandLine.arguments[3] { kill(getpid(), SIGKILL) } }
            try migration.run()
            throw NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "SIGKILL checkpoint was not reached"])
        }
        var count = 0
        func test(_ name: String, _ operation: (Fixture) throws -> Void) throws {
            let fixture = try Fixture()
            do {
                try operation(fixture)
                try fixture.clean()
            } catch {
                try fixture.clean()
                throw error
            }
            count += 1
            print("PASS: \(name)")
        }
        try test("fresh installation leaves ordinary data and preferences unchanged") { f in
            f.preferences = ["existing": "value"]
            try f.write("Documents/unrelated.txt", "user-document", in: f.home)
            try f.migrator().run()
            try f.expect(f.text("Documents/unrelated.txt") == "user-document", "unrelated file changed")
            try f.expect(f.preferences["existing"] as? String == "value", "preferences changed")
            try f.expect(!fm.fileExists(atPath: f.state.appendingPathComponent("journal.plist").path), "unexpected import")
        }
        try test("container-only imports Classic, Next, preferences, bookmarks, caches and support") { f in
            try f.seed()
            try f.migrator().run()
            try f.checkImported()
            try f.write("Documents/nipaplay/watch_history.db", "new-history", in: f.home)
            try f.migrator().run()
            try f.expect(f.text("Documents/nipaplay/watch_history.db") == "new-history", "completed migration reran")
        }
        try test("both locations activate container groups and archive every ordinary entry intact") { f in
            try f.seed()
            try f.seedOrdinary()
            let before = f.root.appendingPathComponent("ordinary-before")
            try fm.copyItem(at: f.home, to: before)
            try f.migrator().run()
            try f.checkImported()
            try f.checkOrdinaryArchived()
            try f.expectSameTree(before, f.state.appendingPathComponent("ordinary-archive"))
            try f.expect(!fm.fileExists(atPath: f.home.appendingPathComponent("Documents/nipaplay/watch_history.db-shm").path), "old SHM mixed into container DB")
            try f.expect(!fm.fileExists(atPath: f.home.appendingPathComponent("Documents/nipaplay/ordinary-only.txt").path), "ordinary-only file merged")
        }
        try test("empty ordinary directory is a placeholder, rather than a conflicting data group") { f in
            try f.seed()
            try fm.createDirectory(at: f.home.appendingPathComponent("Documents/nipaplay"), withIntermediateDirectories: true)
            try f.migrator().run()
            try f.checkImported()
        }
        try test("direct Library SQLite files activate container DB and WAL and archive ordinary-only sidecars") { f in
            try f.seed()
            try f.write("Library/Application Support/nipaplay-images.db", "container-db")
            try f.write("Library/Application Support/nipaplay-images.db-wal", "container-wal")
            try f.write("Library/Application Support/nipaplay-images.db", "ordinary-db", in: f.home)
            try f.write("Library/Application Support/nipaplay-images.db-shm", "ordinary-shm", in: f.home)
            try f.write("Library/Application Support/nipaplay-images.db-journal", "ordinary-journal", in: f.home)
            try f.migrator().run()
            try f.expect(f.text("Library/Application Support/nipaplay-images.db") == "container-db", "container cache DB missing")
            try f.expect(f.text("Library/Application Support/nipaplay-images.db-wal") == "container-wal", "cache WAL generations mixed")
            try f.expect(!fm.fileExists(atPath: f.home.appendingPathComponent("Library/Application Support/nipaplay-images.db-shm").path), "ordinary SHM still active")
            try f.expect(!fm.fileExists(atPath: f.home.appendingPathComponent("Library/Application Support/nipaplay-images.db-journal").path), "ordinary journal still active")
            try f.expect(f.text("ordinary-archive/Library/Application Support/nipaplay-images.db", in: f.state) == "ordinary-db", "ordinary DB archive missing")
            try f.expect(f.text("ordinary-archive/Library/Application Support/nipaplay-images.db-shm", in: f.state) == "ordinary-shm", "ordinary SHM archive missing")
            try f.expect(f.text("ordinary-archive/Library/Application Support/nipaplay-images.db-journal", in: f.state) == "ordinary-journal", "ordinary journal archive missing")
        }
        for point in ["snapshotCopied", "planned", "unitCopied:0", "unitPublished:0", "preferencesWritten", "preferencesPublished"] {
            try test("interruption at \(point) resumes on next launch") { f in
                try f.seed()
                let interrupted = f.migrator()
                interrupted.checkpoint = { if $0 == point { throw Interrupted.simulatedKill } }
                do { try interrupted.run(); throw NSError(domain: "test", code: 2) }
                catch Interrupted.simulatedKill {}
                try f.expect(f.text("Documents/nipaplay/watch_history.db", in: f.source) == "container-history", "source changed during interruption")
                try f.migrator().run()
                try f.checkImported()
            }
        }
        for point in ["ordinaryMoved:0", "ordinaryCopied:0", "ordinaryArchived:0", "ordinaryRetired:0", "unitPublished:0", "preferencesWritten", "preferencesPublished"] {
            try test("both locations interruption at \(point) preserves the archive and resumes") { f in
                try f.seed()
                try f.seedOrdinary()
                let before = f.root.appendingPathComponent("ordinary-before")
                try fm.copyItem(at: f.home, to: before)
                let interrupted = f.migrator()
                interrupted.checkpoint = { if $0 == point { throw Interrupted.simulatedKill } }
                do { try interrupted.run(); throw NSError(domain: "test", code: 2) }
                catch Interrupted.simulatedKill {}
                try f.migrator().run()
                try f.checkImported()
                try f.expectSameTree(before, f.state.appendingPathComponent("ordinary-archive"))
            }
        }
        for point in ["ordinaryMoved:0", "ordinaryCopied:0", "ordinaryArchived:0", "ordinaryRetired:0", "unitPublished:0", "preferencesWritten", "preferencesPublished"] {
            try test("both locations real SIGKILL at \(point) resumes with both versions intact") { f in
                try f.seed()
                try f.seedOrdinary()
                let before = f.root.appendingPathComponent("ordinary-before")
                try fm.copyItem(at: f.home, to: before)
                let worker = Process()
                worker.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                worker.arguments = ["--kill-worker", f.root.path, point]
                try worker.run()
                worker.waitUntilExit()
                try f.expect(worker.terminationReason == .uncaughtSignal && worker.terminationStatus == SIGKILL, "worker was not killed")
                try f.reloadPreferences()
                try f.migrator().run()
                try f.checkImported()
                try f.expectSameTree(before, f.state.appendingPathComponent("ordinary-archive"))
            }
        }
        for point in ["snapshotCopied", "unitCopied:0", "unitPublished:0"] {
            try test("real SIGKILL at \(point) resumes in a new process") { f in
                try f.seed()
                let worker = Process()
                worker.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
                worker.arguments = ["--kill-worker", f.root.path, point]
                try worker.run()
                worker.waitUntilExit()
                try f.expect(worker.terminationReason == .uncaughtSignal && worker.terminationStatus == SIGKILL,
                             "worker was not killed at the migration checkpoint")
                try f.reloadPreferences()
                try f.migrator().run()
                try f.checkImported()
            }
        }
        try test("external destination changes stop recovery without overwriting either version") { f in
            try f.seed()
            let interrupted = f.migrator()
            interrupted.checkpoint = { if $0 == "planned" { throw Interrupted.simulatedKill } }
            do { try interrupted.run() } catch Interrupted.simulatedKill {}
            try f.write("Documents/nipaplay/watch_history.db", "external-change", in: f.home)
            do { try f.migrator().run(); throw Interrupted.simulatedKill }
            catch let error as NSError { try f.expect(error.domain == "NipaPlaySandboxMigration", "wrong failure") }
            try f.expect(f.text("Documents/nipaplay/watch_history.db") == "external-change", "external data overwritten")
            try f.expect(f.text("Documents/nipaplay/watch_history.db", in: f.source) == "container-history", "container changed")
        }
        try test("source changes during snapshot fail before publication and can retry") { f in
            try f.seed()
            let interrupted = f.migrator()
            interrupted.checkpoint = { if $0 == "snapshotCopied" { try f.write("Documents/new.txt", "changed") } }
            do { try interrupted.run(); throw Interrupted.simulatedKill }
            catch let error as NSError { try f.expect(error.domain == "NipaPlaySandboxMigration", "wrong failure") }
            try f.expect(!fm.fileExists(atPath: f.home.appendingPathComponent("Documents/nipaplay").path), "published unverified data")
            try f.migrator().run()
            try f.checkImported()
            try f.expect(f.text("Documents/nipaplay/new.txt") == "changed", "retry missed new file")
        }
        try test("preference changes between launches remain authoritative on recovery") { f in
            try f.seed()
            let interrupted = f.migrator()
            interrupted.checkpoint = { if $0 == "preferencesPublished" { throw Interrupted.simulatedKill } }
            do { try interrupted.run() } catch Interrupted.simulatedKill {}
            f.preferences["flutter.locale"] = "en"
            f.preferences["new-preference"] = "new"
            try f.writeOrdinaryPreferences()
            try f.migrator().run()
            try f.expect(f.preferences["flutter.locale"] as? String == "en", "new preference overwritten")
            try f.expect(f.preferences["new-preference"] as? String == "new", "new preference lost")
        }
        try test("before preference publication only container keys are authoritative on recovery") { f in
            try f.seed()
            try f.seedOrdinary()
            let interrupted = f.migrator()
            interrupted.checkpoint = { if $0 == "unitCopied:0" { throw Interrupted.simulatedKill } }
            do { try interrupted.run() } catch Interrupted.simulatedKill {}
            f.preferences["flutter.locale"] = "ja"
            f.preferences["new-old-key"] = true
            try f.writeOrdinaryPreferences()
            try f.migrator().run()
            try f.checkImported()
            try f.expect(f.preferences["ordinary-only"] == nil && f.preferences["new-old-key"] == nil, "old domain keys retained")
        }
        try test("missing container preference plist clears old domain and archives old plist intact") { f in
            try f.seed()
            try f.seedOrdinary()
            try fm.removeItem(at: f.source.appendingPathComponent("Library/Preferences/\(bundleID).plist"))
            let before = try Data(contentsOf: f.home.appendingPathComponent("Library/Preferences/\(bundleID).plist"))
            try f.migrator().run()
            try f.expect(f.preferences.isEmpty, "missing container domain kept ordinary keys")
            try f.expect(Data(contentsOf: f.state.appendingPathComponent("ordinary-archive/Library/Preferences/\(bundleID).plist")) == before, "old plist bytes changed")
        }
        try test("changed ordinary group blocks archival without overwriting either version") { f in
            try f.seed()
            try f.seedOrdinary()
            let interrupted = f.migrator()
            interrupted.checkpoint = { if $0 == "planned" { throw Interrupted.simulatedKill } }
            do { try interrupted.run() } catch Interrupted.simulatedKill {}
            try f.write("Documents/nipaplay/watch_history.db", "external-change", in: f.home)
            do { try f.migrator().run(); throw Interrupted.simulatedKill }
            catch let error as NSError { try f.expect(error.domain == "NipaPlaySandboxMigration", "wrong failure") }
            try f.expect(f.text("Documents/nipaplay/watch_history.db") == "external-change", "ordinary changes overwritten")
            try f.expect(f.text("Documents/nipaplay/watch_history.db", in: f.source) == "container-history", "container changed")
        }
        try test("partly deleted retired staging resumes using the complete verified ordinary archive") { f in
            try f.seed()
            try f.seedOrdinary()
            let before = f.root.appendingPathComponent("ordinary-before")
            try fm.copyItem(at: f.home, to: before)
            let interrupted = f.migrator()
            interrupted.checkpoint = { if $0 == "ordinaryRetired:0" { throw Interrupted.simulatedKill } }
            do { try interrupted.run() } catch Interrupted.simulatedKill {}
            let journal = try PropertyListDecoder().decode(SandboxMigration.Journal.self, from: Data(contentsOf: f.state.appendingPathComponent("journal.plist")))
            let retired = f.home.appendingPathComponent(journal.archives[0].retired)
            try fm.removeItem(at: retired.appendingPathComponent("watch_history.db"))
            try f.migrator().run()
            try f.checkImported()
            try f.expectSameTree(before, f.state.appendingPathComponent("ordinary-archive"))
            try f.expect(!fm.fileExists(atPath: retired.path), "partial redundant staging not cleaned")
        }
        try test("ordinary-only SQLite sidecar reappearing after archival blocks publication") { f in
            try f.seed()
            try f.write("Library/Application Support/nipaplay-images.db", "container-db")
            try f.write("Library/Application Support/nipaplay-images.db-shm", "ordinary-shm", in: f.home)
            let interrupted = f.migrator()
            interrupted.checkpoint = { if $0 == "unitCopied:0" { throw Interrupted.simulatedKill } }
            do { try interrupted.run() } catch Interrupted.simulatedKill {}
            try f.write("Library/Application Support/nipaplay-images.db-shm", "external-shm", in: f.home)
            do { try f.migrator().run(); throw Interrupted.simulatedKill }
            catch let error as NSError { try f.expect(error.domain == "NipaPlaySandboxMigration", "wrong failure") }
            try f.expect(f.text("Library/Application Support/nipaplay-images.db-shm") == "external-shm", "new sidecar overwritten")
            try f.expect(f.text("ordinary-archive/Library/Application Support/nipaplay-images.db-shm", in: f.state) == "ordinary-shm", "old sidecar archive changed")
        }
        try test("corrupt ordinary archive blocks recovery and retains ordinary staging and container") { f in
            try f.seed()
            try f.seedOrdinary()
            let interrupted = f.migrator()
            interrupted.checkpoint = { if $0 == "ordinaryArchived:0" { throw Interrupted.simulatedKill } }
            do { try interrupted.run() } catch Interrupted.simulatedKill {}
            try f.write("ordinary-archive/Documents/nipaplay/watch_history.db", "damaged", in: f.state)
            do { try f.migrator().run(); throw Interrupted.simulatedKill }
            catch let error as NSError { try f.expect(error.domain == "NipaPlaySandboxMigration", "wrong failure") }
            let journal = try PropertyListDecoder().decode(SandboxMigration.Journal.self, from: Data(contentsOf: f.state.appendingPathComponent("journal.plist")))
            try f.expect(f.text(journal.archives[0].temporary + "/watch_history.db") == "ordinary-history", "ordinary staging lost")
            try f.expect(f.text("Documents/nipaplay/watch_history.db", in: f.source) == "container-history", "container changed")
        }
        try test("corrupt archive blocks recovery and leaves the original container intact") { f in
            try f.seed()
            let interrupted = f.migrator()
            interrupted.checkpoint = { if $0 == "planned" { throw Interrupted.simulatedKill } }
            do { try interrupted.run() } catch Interrupted.simulatedKill {}
            try f.write("container-copy/Documents/nipaplay/watch_history.db", "damaged", in: f.state)
            do { try f.migrator().run(); throw Interrupted.simulatedKill }
            catch let error as NSError { try f.expect(error.domain == "NipaPlaySandboxMigration", "wrong failure") }
            try f.expect(f.text("Documents/nipaplay/watch_history.db", in: f.source) == "container-history", "source changed")
            try f.expect(!fm.fileExists(atPath: f.home.appendingPathComponent("Documents/nipaplay").path), "corrupt data published")
        }
        try test("real SQLite history survives migration and passes integrity_check") { f in
            try f.seed()
            let database = f.source.appendingPathComponent("Documents/nipaplay/real-history.db")
            func sqlite(_ location: URL, _ sql: String) throws -> String {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
                process.arguments = [location.path, sql]
                let output = Pipe()
                process.standardOutput = output
                try process.run()
                process.waitUntilExit()
                try f.expect(process.terminationStatus == 0, "SQLite fixture failed")
                return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            }
            _ = try sqlite(database, "CREATE TABLE history (id INTEGER PRIMARY KEY, title TEXT); INSERT INTO history VALUES (1, 'Classic user history');")
            try f.migrator().run()
            let output = try sqlite(f.home.appendingPathComponent("Documents/nipaplay/real-history.db"), "PRAGMA integrity_check; SELECT title FROM history;")
            try f.expect(output == "ok\nClassic user history\n", "SQLite content or integrity changed")
        }
        try test("symlinks are copied as links without traversing external media") { f in
            try f.seed()
            let external = f.root.appendingPathComponent("external-media")
            try fm.createDirectory(at: external, withIntermediateDirectories: true)
            try f.write("huge-video.mkv", "external", in: external)
            let link = f.source.appendingPathComponent("Documents/nipaplay/media-link")
            try fm.createSymbolicLink(at: link, withDestinationURL: external)
            try fm.createSymbolicLink(atPath: f.source.appendingPathComponent("Documents/nipaplay/broken-link").path,
                                     withDestinationPath: "/missing/media")
            try f.migrator().run()
            try f.expect(fm.destinationOfSymbolicLink(atPath: f.home.appendingPathComponent("Documents/nipaplay/media-link").path) == external.path, "link dereferenced")
            try f.expect(fm.destinationOfSymbolicLink(atPath: f.home.appendingPathComponent("Documents/nipaplay/broken-link").path) == "/missing/media", "broken link lost")
        }
        try test("stale external player socket is indexed, remains in the container and does not block migration") { f in
            try f.seed()
            let alias = URL(fileURLWithPath: "/tmp/nipa-ipc-" + UUID().uuidString)
            try fm.createSymbolicLink(at: alias, withDestinationURL: f.source.appendingPathComponent("tmp"))
            defer { try? fm.removeItem(at: alias) }
            let socketFile = alias.appendingPathComponent("mpv.sock")
            let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
            try f.expect(descriptor >= 0, "socket fixture failed")
            defer { close(descriptor) }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let pathBytes = Array(socketFile.path.utf8) + [0]
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathBytes) }
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            try f.expect(result == 0, "socket bind failed")
            try f.migrator().run()
            try f.checkImported()
            try f.expect(fm.attributesOfItem(atPath: f.source.appendingPathComponent("tmp/mpv.sock").path)[.type] as? FileAttributeType == .typeSocket,
                         "source socket changed")
            let index = try PropertyListSerialization.propertyList(from: Data(contentsOf: f.state.appendingPathComponent("volatile-sockets.plist")), format: nil) as! [String]
            try f.expect(index == ["/tmp/mpv.sock"], "socket metadata not indexed")
        }
        try test("shared container mirrors stay out of the user's Library") { f in
            try f.seed()
            // A real container links shared user data back to ~/Library with relative paths.
            for name in ["AddressBook", "SyncServices"] {
                try fm.createDirectory(at: f.source.appendingPathComponent("Library/Application Support"), withIntermediateDirectories: true)
                try fm.createSymbolicLink(atPath: f.source.appendingPathComponent("Library/Application Support/\(name)").path,
                                          withDestinationPath: "../../../../../Application Support/\(name)")
                try f.write("Library/Application Support/\(name)/data", "user-\(name)", in: f.home)
            }
            try fm.createDirectory(at: f.source.appendingPathComponent("Library/Images"), withIntermediateDirectories: true)
            try fm.createSymbolicLink(atPath: f.source.appendingPathComponent("Library/Images/People").path,
                                      withDestinationPath: "../../../../../Images/People")
            try f.write("Library/Application Support/iCloud/Accounts/container", "container-icloud")
            try f.write("Library/Application Support/iCloud/Accounts/user", "user-icloud", in: f.home)
            try f.write("Library/Application Support/CrashReporter/report.plist", "container-report")
            try f.write("Library/Caches/flutter_engine/shader", "container-shader")
            try f.write("Library/Caches/flutter_engine/shader", "user-shader", in: f.home)
            try f.migrator().run()
            try f.checkImported()
            for name in ["AddressBook", "SyncServices"] {
                try f.expect(f.text("Library/Application Support/\(name)/data") == "user-\(name)", "\(name) replaced")
            }
            try f.expect(f.text("Library/Application Support/iCloud/Accounts/user") == "user-icloud", "iCloud replaced")
            try f.expect(!fm.fileExists(atPath: f.home.appendingPathComponent("Library/Application Support/iCloud/Accounts/container").path), "container iCloud published")
            try f.expect(!fm.fileExists(atPath: f.home.appendingPathComponent("Library/Application Support/CrashReporter").path), "CrashReporter published")
            try f.expect(f.text("Library/Caches/flutter_engine/shader") == "user-shader", "shared cache replaced")
            var info = stat()
            try f.expect(lstat(f.home.appendingPathComponent("Library/Images/People").path, &info) != 0, "People link published")
            try f.expect(f.text("container-copy/Library/Application Support/iCloud/Accounts/container", in: f.state) == "container-icloud", "container mirror not archived")
        }
        print("All \(count) migration tests passed; fixtures were isolated temporary directories.")
    }
}
