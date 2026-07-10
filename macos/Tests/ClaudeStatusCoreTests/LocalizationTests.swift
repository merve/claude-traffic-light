import XCTest
@testable import ClaudeStatusCore

final class LocalizationTests: XCTestCase {

    func testEnglishFallbackForUnknownLanguage() {
        // A language not present in tables → falls back to English.
        XCTAssertNil(L10n.tables["xx"])
        XCTAssertEqual((L10n.tables["xx"] ?? L10n.english).localeID, "en")
    }

    func testLabelMapping() {
        let l = L10n.english
        XCTAssertEqual(l.label(for: .red), l.asking)
        XCTAssertEqual(l.label(for: .yellow), l.working)
        XCTAssertEqual(l.label(for: .green), l.done)
    }

    func testTurkishTableExists() {
        let tr = try? XCTUnwrap(L10n.tables["tr"])
        XCTAssertEqual(tr?.localeID, "tr")
        XCTAssertEqual(tr?.notifyTitle, "Claude seni bekliyor")
    }

    func testCurrentReturnsAValidTable() {
        // Whatever the system language, must return a valid, non-empty table.
        let l = L10n.current
        XCTAssertFalse(l.localeID.isEmpty)
        XCTAssertFalse(l.working.isEmpty)
    }

    // Every language table must fill all fields (catch missing translations = empty string).
    func testAllTablesHaveNonEmptyFields() {
        for (code, l) in L10n.tables {
            let fields: [(String, String)] = [
                ("working", l.working), ("asking", l.asking), ("done", l.done),
                ("noSessions", l.noSessions), ("waitingWord", l.waitingWord),
                ("workingWord", l.workingWord), ("doneWord", l.doneWord),
                ("refresh", l.refresh), ("quit", l.quit),
                ("notifyTitle", l.notifyTitle), ("notifyMenu", l.notifyMenu),
                ("localeID", l.localeID),
            ]
            for (name, value) in fields {
                XCTAssertFalse(value.isEmpty, "[\(code)] '\(name)' must not be empty")
            }
        }
    }

    func testExpectedLanguagesPresent() {
        for code in ["en", "tr", "es", "de", "fr", "it", "pt", "ru", "ja", "zh", "ko"] {
            XCTAssertNotNil(L10n.tables[code], "missing table for \(code)")
        }
    }
}
