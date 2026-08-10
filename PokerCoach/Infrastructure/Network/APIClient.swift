import Foundation

/// Minimal JSON transport over `URLSession`. It owns status-to-`APIError`
/// mapping so every caller reacts to the same typed failures.
struct APIClient: Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func send<Response: Decodable & Sendable>(
        _ method: String,
        _ path: String,
        body: (some Encodable & Sendable)? = Optional<Empty>.none,
        accessToken: String? = nil
    ) async throws -> Response {
        let data = try await perform(method, path, body: body, accessToken: accessToken)
        do {
            return try APIDateCoding.decoder().decode(Response.self, from: data)
        } catch {
            throw APIError.malformedResponse
        }
    }

    func sendWithoutResponse(
        _ method: String,
        _ path: String,
        body: (some Encodable & Sendable)? = Optional<Empty>.none,
        accessToken: String? = nil
    ) async throws {
        _ = try await perform(method, path, body: body, accessToken: accessToken)
    }

    private func perform(
        _ method: String,
        _ path: String,
        body: (some Encodable & Sendable)?,
        accessToken: String?
    ) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try APIDateCoding.encoder().encode(body)
        }

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
        guard (200 ..< 300).contains(http.statusCode) else {
            throw mapFailure(status: http.statusCode, data: data, headers: http)
        }
        return data
    }

    private func mapFailure(
        status: Int,
        data: Data,
        headers: HTTPURLResponse
    ) -> APIError {
        let code = (try? APIDateCoding.decoder().decode(ErrorEnvelopeDTO.self, from: data))?
            .error.code

        switch status {
        case 400:
            return .validationFailed
        case 401:
            return code == "reauthenticationRequired" ? .reauthenticationRequired : .unauthorized
        case 409:
            return .identityConflict
        case 413:
            return .batchTooLarge
        case 429:
            let retryAfter = headers.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init) ?? 1
            return .rateLimited(retryAfter: retryAfter)
        default:
            return .server(status: status)
        }
    }

    struct Empty: Codable, Sendable {}
}
