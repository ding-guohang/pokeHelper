import Foundation
import XCTest
@testable import PokerCoach

final class PasswordPolicyTests: XCTestCase {
    private let policy = PasswordPolicy(blocklist: ["correct horse battery staple"])

    func testAcceptsPasswordsAtTheScalarBoundaries() throws {
        let fifteen = String(repeating: "a", count: 15)
        let hundredTwentyEight = String(repeating: "a", count: 128)

        XCTAssertEqual(try policy.validate(fifteen), fifteen)
        XCTAssertEqual(try policy.validate(hundredTwentyEight), hundredTwentyEight)
    }

    func testRejectsPasswordsOutsideTheScalarBoundaries() {
        assertRejects(String(repeating: "a", count: 14), .tooShort)
        assertRejects(String(repeating: "a", count: 129), .tooLong)
    }

    // The server counts Unicode scalars, not UTF-8 bytes. A 15-emoji password
    // is 60 bytes but exactly 15 scalars, so it must be accepted here too or
    // the client would reject inputs the server considers valid.
    func testCountsUnicodeScalarsRatherThanBytes() throws {
        let fifteenEmoji = String(repeating: "🂡", count: 15)

        XCTAssertEqual(try policy.validate(fifteenEmoji), fifteenEmoji)
        XCTAssertEqual(fifteenEmoji.unicodeScalars.count, 15)
        XCTAssertGreaterThan(fifteenEmoji.utf8.count, 15)
    }

    // Parity with the Go policy: both sides normalize to NFC before counting,
    // so a decomposed string and its composed form get the same verdict.
    func testNormalizesToNFCBeforeCounting() throws {
        let decomposed = String(repeating: "e\u{0301}", count: 15)
        let composed = String(repeating: "\u{00E9}", count: 15)

        let validated = try policy.validate(decomposed)

        XCTAssertEqual(validated, composed)
        XCTAssertEqual(validated.unicodeScalars.count, 15)
    }

    func testDecomposedInputBelowTheLimitAfterNormalizationIsRejected() {
        // 14 composed scalars written in decomposed form: 28 scalars raw, but
        // only 14 once normalized, so it must be rejected.
        assertRejects(String(repeating: "e\u{0301}", count: 14), .tooShort)
    }

    func testRejectsBlockedPasswordsCaseInsensitively() {
        assertRejects("correct horse battery staple", .blocked)
        assertRejects("Correct Horse Battery Staple", .blocked)
    }

    func testAppliesNoCompositionRule() throws {
        // Fifteen identical lowercase letters carry no digit, symbol, or
        // uppercase character and must still be accepted.
        XCTAssertNoThrow(try policy.validate(String(repeating: "z", count: 15)))
    }

    func testRejectsMalformedScalars() {
        assertRejects("\u{FFFE}" + String(repeating: "a", count: 20), .malformed)
    }

    func testEveryFailureCarriesARecoverableChineseMessage() {
        for failure in PasswordPolicy.Failure.allCases {
            XCTAssertFalse(
                failure.recoverySuggestion.isEmpty,
                "\(failure) must explain how to recover"
            )
            XCTAssertTrue(
                failure.recoverySuggestion.contains(where: \.isChineseCharacter),
                "\(failure) must be described in Chinese"
            )
        }
    }

    private func assertRejects(
        _ password: String,
        _ expected: PasswordPolicy.Failure,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try policy.validate(password), file: file, line: line) { error in
            XCTAssertEqual(error as? PasswordPolicy.Failure, expected, file: file, line: line)
        }
    }
}

extension Character {
    var isChineseCharacter: Bool {
        unicodeScalars.contains { (0x4E00 ... 0x9FFF).contains($0.value) }
    }
}
