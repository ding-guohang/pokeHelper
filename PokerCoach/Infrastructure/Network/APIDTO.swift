import Foundation

/// Wire shapes shared by the account endpoints. Field names and the RFC 3339
/// date encoding must match the Go service exactly.
struct SessionTokensDTO: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: Date
    let refreshExpiresAt: Date
    let userID: UUID
    let sessionID: UUID
    let recentAuthAt: Date

    func session(email: String?) -> StoredSession {
        StoredSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessExpiresAt: accessExpiresAt,
            refreshExpiresAt: refreshExpiresAt,
            userID: userID,
            sessionID: sessionID,
            recentAuthAt: recentAuthAt,
            email: email
        )
    }
}

struct DeviceDescriptor: Codable, Sendable, Equatable {
    let deviceID: UUID
    let displayName: String
    let platform: String
    let appVersion: String
}

struct DeviceSessionDTO: Codable, Sendable, Equatable, Identifiable {
    let sessionID: UUID
    let deviceID: UUID
    let displayName: String
    let platform: String
    let appVersion: String
    let createdAt: Date
    let lastActiveAt: Date
    let current: Bool

    var id: UUID { sessionID }
}

struct ErrorEnvelopeDTO: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        let code: String
        let requestID: String
    }

    let error: Body
}

/// Thread-safe RFC 3339 conversion.
///
/// `ISO8601DateFormatter` is not `Sendable`, and the JSON coding strategies are
/// `@Sendable` closures, so the formatters are wrapped behind a lock instead of
/// being captured directly or rebuilt for every value.
private final class RFC3339Coder: @unchecked Sendable {
    static let shared = RFC3339Coder()

    private let mutex = NSLock()
    private let fractional = RFC3339Coder.makeFormatter(withFractionalSeconds: true)
    private let plain = RFC3339Coder.makeFormatter(withFractionalSeconds: false)

    func date(from text: String) -> Date? {
        mutex.withLock { fractional.date(from: text) ?? plain.date(from: text) }
    }

    func string(from date: Date) -> String {
        mutex.withLock { fractional.string(from: date) }
    }

    private static func makeFormatter(
        withFractionalSeconds fractionalSeconds: Bool
    ) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

enum APIDateCoding {
    /// UTC RFC 3339 with at most millisecond precision, matching the server.
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = RFC3339Coder.shared.date(from: text) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "无法解析时间 \(text)"
                    )
                )
            }
            return date
        }
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(RFC3339Coder.shared.string(from: date))
        }
        return encoder
    }
}
