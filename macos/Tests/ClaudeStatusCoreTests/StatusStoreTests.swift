import XCTest
import Foundation
@testable import ClaudeStatusCore

final class StatusStoreTests: XCTestCase {

    // Isolated temporary status directory per test.
    private var tmpDir: URL!
    private var store: StatusStore!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudestatus-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        store = StatusStore(statusDir: tmpDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    // MARK: - Helpers

    /// Writes an <id>.json status file with the given fields.
    @discardableResult
    private func writeStatus(id: String, state: String, project: String = "proj",
                             cwd: String = "/tmp/proj", ts: TimeInterval? = nil,
                             pid: Int32? = nil, platform: String? = nil,
                             appPath: String? = nil) throws -> URL {
        var obj: [String: Any] = ["state": state, "project": project, "cwd": cwd]
        obj["ts"] = Int(ts ?? Date().timeIntervalSince1970)
        if let pid = pid { obj["session_pid"] = Int(pid) }
        if let platform = platform { obj["platform"] = platform }
        if let appPath = appPath { obj["app_path"] = appPath }
        let url = tmpDir.appendingPathComponent("\(id).json")
        let data = try JSONSerialization.data(withJSONObject: obj)
        try data.write(to: url)
        return url
    }

    private var livePID: Int32 { ProcessInfo.processInfo.processIdentifier }

    /// Produces a guaranteed-dead PID: start a short-lived process and wait for it to exit.
    private func deadPID() throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try p.run()
        p.waitUntilExit()
        return p.processIdentifier
    }

    // MARK: - load(): basics

    func testLoadEmptyDirectory() {
        XCTAssertEqual(store.load().count, 0)
    }

    func testLoadMissingDirectoryReturnsEmpty() {
        let missing = StatusStore(statusDir: tmpDir.appendingPathComponent("nope"))
        XCTAssertEqual(missing.load().count, 0)
    }

    func testLoadParsesFields() throws {
        try writeStatus(id: "sess1", state: "yellow", project: "myproj",
                        cwd: "/tmp/myproj", pid: livePID, platform: "vscode")
        let sessions = store.load()
        XCTAssertEqual(sessions.count, 1)
        let s = sessions[0]
        XCTAssertEqual(s.sessionID, "sess1")
        XCTAssertEqual(s.state, .yellow)
        XCTAssertEqual(s.project, "myproj")
        XCTAssertEqual(s.cwd, "/tmp/myproj")
        XCTAssertEqual(s.platform, "vscode")
    }

    func testProjectFallsBackToCwdLastComponent() throws {
        // When there's no project field, the last component of cwd is used.
        let url = tmpDir.appendingPathComponent("sess2.json")
        let obj: [String: Any] = ["state": "green", "cwd": "/a/b/coolproject",
                                  "ts": Int(Date().timeIntervalSince1970), "session_pid": Int(livePID)]
        try JSONSerialization.data(withJSONObject: obj).write(to: url)
        let s = try XCTUnwrap(store.load().first)
        XCTAssertEqual(s.project, "coolproject")
    }

    func testPlatformDefaultsToUnknown() throws {
        try writeStatus(id: "sess3", state: "green", pid: livePID) // no platform field
        let s = try XCTUnwrap(store.load().first)
        XCTAssertEqual(s.platform, "unknown")
    }

    func testAppPathParsedAndDefaultsEmpty() throws {
        try writeStatus(id: "withapp", state: "yellow", pid: livePID,
                        platform: "terminal", appPath: "/Applications/iTerm.app")
        let s = try XCTUnwrap(store.load().first)
        XCTAssertEqual(s.appPath, "/Applications/iTerm.app")

        try writeStatus(id: "noapp", state: "yellow", pid: livePID) // no app_path field
        let noapp = try XCTUnwrap(store.load().first { $0.sessionID == "noapp" })
        XCTAssertEqual(noapp.appPath, "") // default empty
    }

    func testInvalidJSONIsSkipped() throws {
        try "{ broken json".data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("bad.json"))
        try writeStatus(id: "ok", state: "red", pid: livePID)
        XCTAssertEqual(store.load().count, 1) // only the valid one
    }

    func testUnknownStateIsSkipped() throws {
        try writeStatus(id: "weird", state: "purple", pid: livePID)
        XCTAssertEqual(store.load().count, 0)
    }

    func testNonJSONFilesIgnored() throws {
        try "hello".data(using: .utf8)!.write(to: tmpDir.appendingPathComponent("note.txt"))
        try writeStatus(id: "ok", state: "yellow", pid: livePID)
        XCTAssertEqual(store.load().count, 1)
    }

    // MARK: - PID liveness

    func testDeadPIDSessionDroppedAndFileDeleted() throws {
        let dead = try deadPID()
        let url = try writeStatus(id: "deadone", state: "yellow", pid: dead)
        XCTAssertEqual(store.load().count, 0, "session with a dead PID should be dropped")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "file should be deleted")
    }

    func testLivePIDSessionKept() throws {
        try writeStatus(id: "liveone", state: "yellow", pid: livePID)
        XCTAssertEqual(store.load().count, 1)
    }

    func testIsProcessAlive() throws {
        XCTAssertTrue(StatusStore.isProcessAlive(livePID))
        XCTAssertTrue(StatusStore.isProcessAlive(1))        // launchd: EPERM → alive
        XCTAssertTrue(StatusStore.isProcessAlive(0))        // <= 0 → treated as alive
        XCTAssertFalse(StatusStore.isProcessAlive(try deadPID()))
    }

    // MARK: - Old format (no pid) staleness

    func testOldFormatFreshKept() throws {
        try writeStatus(id: "fresh", state: "yellow", ts: Date().timeIntervalSince1970) // no pid
        XCTAssertEqual(store.load().count, 1)
    }

    func testOldFormatStaleDroppedAndDeleted() throws {
        let old = Date().timeIntervalSince1970 - (StatusStore.staleAfter + 60)
        let url = try writeStatus(id: "stale", state: "yellow", ts: old) // no pid
        XCTAssertEqual(store.load().count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Sorting & aggregate

    func testSortingRedFirstThenNewest() throws {
        let now = Date().timeIntervalSince1970
        try writeStatus(id: "g", state: "green", ts: now, pid: livePID)
        try writeStatus(id: "y", state: "yellow", ts: now, pid: livePID)
        try writeStatus(id: "r_old", state: "red", ts: now - 100, pid: livePID)
        try writeStatus(id: "r_new", state: "red", ts: now, pid: livePID)

        let ordered = store.load().map { $0.sessionID }
        // Red first (newest → oldest), then yellow, then green.
        XCTAssertEqual(ordered, ["r_new", "r_old", "y", "g"])
    }

    func testAggregatePicksHighestPriority() {
        func mk(_ st: State) -> SessionStatus {
            SessionStatus(sessionID: "x", state: st, project: "p", cwd: "/", ts: Date(), platform: "unknown")
        }
        XCTAssertEqual(store.aggregate([mk(.green), mk(.yellow), mk(.red)]), .red)
        XCTAssertEqual(store.aggregate([mk(.green), mk(.yellow)]), .yellow)
        XCTAssertEqual(store.aggregate([mk(.green)]), .green)
        XCTAssertEqual(store.aggregate([]), .green) // idle when there are no sessions
    }

    // MARK: - State

    func testStatePriorityOrder() {
        XCTAssertGreaterThan(State.red.priority, State.yellow.priority)
        XCTAssertGreaterThan(State.yellow.priority, State.green.priority)
    }

    func testStateEmoji() {
        XCTAssertEqual(State.red.emoji, "🔴")
        XCTAssertEqual(State.yellow.emoji, "🟡")
        XCTAssertEqual(State.green.emoji, "🟢")
    }
}
