import Foundation

/// Client-side mirror of the server password policy.
///
/// Both sides normalize to NFC and count Unicode scalars, so a password the
/// app accepts is one the server accepts. Validating here only saves a round
/// trip; the server remains the authority.
struct PasswordPolicy: Sendable {
    enum Failure: Error, Equatable, CaseIterable {
        case tooShort
        case tooLong
        case blocked
        case malformed

        var recoverySuggestion: String {
            switch self {
            case .tooShort:
                "密码至少需要 15 个字符，请再补充一些内容。"
            case .tooLong:
                "密码最多 128 个字符，请缩短后重试。"
            case .blocked:
                "这个密码过于常见，请换一个不容易被猜到的密码。"
            case .malformed:
                "密码包含无法识别的字符，请重新输入。"
            }
        }
    }

    static let minimumScalars = 15
    static let maximumScalars = 128

    private let blocklist: Set<String>

    init(blocklist: Set<String> = []) {
        self.blocklist = Set(blocklist.map { $0.lowercased() })
    }

    /// Returns the NFC-normalized password to send to the server, or throws the
    /// specific reason it cannot be used.
    func validate(_ raw: String) throws -> String {
        let normalized = raw.precomposedStringWithCanonicalMapping

        guard normalized.unicodeScalars.allSatisfy(isUsableScalar) else {
            throw Failure.malformed
        }

        let scalarCount = normalized.unicodeScalars.count
        guard scalarCount >= Self.minimumScalars else {
            throw Failure.tooShort
        }
        guard scalarCount <= Self.maximumScalars else {
            throw Failure.tooLong
        }
        guard !blocklist.contains(normalized.lowercased()) else {
            throw Failure.blocked
        }

        return normalized
    }

    private func isUsableScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .surrogate, .unassigned, .privateUse, .control:
            false
        default:
            !scalar.properties.isNoncharacterCodePoint
        }
    }
}
