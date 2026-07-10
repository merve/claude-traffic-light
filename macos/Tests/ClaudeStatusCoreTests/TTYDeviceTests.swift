import XCTest
@testable import ClaudeStatusCore

final class TTYDeviceTests: XCTestCase {
    func testPlainTTYNameGetsDevPrefix() {
        XCTAssertEqual(TTYDevice.parse(psOutput: "ttys000"), "/dev/ttys000")
    }

    func testTrimsWhitespaceAndNewline() {
        XCTAssertEqual(TTYDevice.parse(psOutput: "  ttys004\n"), "/dev/ttys004")
    }

    func testNoControllingTerminalReturnsNil() {
        // "??" is what `ps` prints for processes with no controlling tty (e.g. detached).
        XCTAssertEqual(TTYDevice.parse(psOutput: "??"), nil)
    }

    func testEmptyOutputReturnsNil() {
        XCTAssertEqual(TTYDevice.parse(psOutput: ""), nil)
        XCTAssertEqual(TTYDevice.parse(psOutput: "   "), nil)
    }

    func testAlreadyPrefixedPathIsNotDoublePrefixed() {
        XCTAssertEqual(TTYDevice.parse(psOutput: "/dev/ttys002"), "/dev/ttys002")
    }
}
