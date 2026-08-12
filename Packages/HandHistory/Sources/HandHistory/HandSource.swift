import CryptoKit
import Foundation

/// The raw imported text and the identity derived from it.
///
/// Two imports are "the same hand" when their identities match. The identity is
/// the SHA-256 of the text with line endings normalized to LF, so a hand copied
/// on Windows (CRLF) and the same hand copied on macOS (LF) collide as they
/// should, while genuinely different text does not. The raw text is retained
/// verbatim — normalization affects only the hash, never what is stored.
public struct HandSource: Hashable, Sendable, Codable {
    public let rawText: String
    /// Lowercase hex SHA-256 of `rawText` with CRLF/CR folded to LF.
    public let identity: String

    public init(rawText: String) {
        self.rawText = rawText
        self.identity = Self.identity(of: rawText)
    }

    static func identity(of rawText: String) -> String {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
