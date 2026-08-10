import Foundation
import TrainingDomain

/// Why a synchronization run was started. Kept for diagnostics and so the UI
/// can distinguish a user-triggered retry from background activity.
enum SyncReason: String, Sendable, Equatable {
    case launch
    case authenticated
    case foreground
    case networkRestored
    case decisionCompleted
    case manualRetry
}

enum SyncStatus: Equatable, Sendable {
    /// No account, so there is nothing to synchronize. Training is unaffected.
    case idle
    case syncing
    case upToDate(at: Date)
    case failed(message: String)
}

struct UploadBatch: Sendable, Equatable {
    let idempotencyKey: UUID
    let body: Data
}

struct UploadAcknowledgement: Decodable, Sendable, Equatable {
    let acceptedEventIDs: [UUID]
    let checkpoint: UInt64
}

struct RemoteEventPage: Decodable, Sendable, Equatable {
    let events: [TrainingEvent]
    let checkpoint: UInt64
    let hasMore: Bool
}

protocol SyncAPI: Sendable {
    func upload(_ batch: UploadBatch, accessToken: String) async throws -> UploadAcknowledgement
    func pull(after checkpoint: UInt64, limit: Int, accessToken: String) async throws
        -> RemoteEventPage
}

/// `SyncAPI` over the shared transport.
struct RemoteSyncAPI: SyncAPI {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func upload(
        _ batch: UploadBatch,
        accessToken: String
    ) async throws -> UploadAcknowledgement {
        var request = URLRequest(url: baseURL.appending(path: "v1/sync/events"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(
            batch.idempotencyKey.uuidString.lowercased(),
            forHTTPHeaderField: "Idempotency-Key"
        )
        // The stored bytes are sent verbatim: re-encoding could change the
        // hash the server matched the first attempt against.
        request.httpBody = batch.body
        return try await send(request)
    }

    func pull(
        after checkpoint: UInt64,
        limit: Int,
        accessToken: String
    ) async throws -> RemoteEventPage {
        var components = URLComponents(
            url: baseURL.appending(path: "v1/sync/events"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "after", value: String(checkpoint)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components?.url else {
            throw APIError.malformedResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    private func send<Response: Decodable & Sendable>(
        _ request: URLRequest
    ) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw error.code == .timedOut ? APIError.timedOut : APIError.offline
        } catch {
            throw APIError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.malformedResponse
        }
        switch http.statusCode {
        case 200 ..< 300:
            break
        case 400:
            throw APIError.validationFailed
        case 401:
            throw APIError.unauthorized
        case 409:
            throw APIError.identityConflict
        case 413:
            throw APIError.batchTooLarge
        default:
            throw APIError.server(status: http.statusCode)
        }

        do {
            return try SyncEventCoding.decoder().decode(Response.self, from: data)
        } catch {
            throw APIError.malformedResponse
        }
    }
}

/// Decoding for events arriving from the server. The date format matches the
/// canonical upload encoding exactly.
enum SyncEventCoding {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = RemoteEventDateParser.date(from: text) else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "无法解析事件时间 \(text)"
                    )
                )
            }
            return date
        }
        return decoder
    }
}

enum RemoteEventDateParser {
    static func date(from text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
