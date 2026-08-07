import AuthenticationServices
import CryptoKit
import Foundation

struct AppleCredential: Sendable, Equatable {
    let identityToken: String
    /// The raw nonce this app generated. The server compares it against the
    /// token's nonce claim, so it must be sent alongside the credential.
    let nonce: String
}

enum AppleAuthorizationError: Error, Equatable {
    case cancelled
    case unavailable

    var recoverySuggestion: String {
        switch self {
        case .cancelled:
            "已取消 Apple 登录。"
        case .unavailable:
            "暂时无法使用 Apple 登录，请稍后重试或改用邮箱登录。"
        }
    }
}

protocol AppleAuthorizationClient: Sendable {
    func requestCredential() async throws -> AppleCredential
}

/// AuthenticationServices adapter.
///
/// Apple embeds the SHA-256 of the nonce we hand to the request, so the raw
/// nonce is kept and sent to our server, which compares it against the claim.
final class SystemAppleAuthorizationClient: NSObject, AppleAuthorizationClient,
    ASAuthorizationControllerDelegate, @unchecked Sendable
{
    private var continuation: CheckedContinuation<AppleCredential, Error>?
    private var rawNonce = ""

    func requestCredential() async throws -> AppleCredential {
        let nonce = Self.makeNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        request.nonce = Self.sha256(nonce)

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.rawNonce = nonce
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let identityToken = String(data: tokenData, encoding: .utf8)
        else {
            continuation?.resume(throwing: AppleAuthorizationError.unavailable)
            continuation = nil
            return
        }

        continuation?.resume(
            returning: AppleCredential(identityToken: identityToken, nonce: rawNonce)
        )
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let failure: AppleAuthorizationError =
            (error as? ASAuthorizationError)?.code == .canceled ? .cancelled : .unavailable
        continuation?.resume(throwing: failure)
        continuation = nil
    }

    private static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return UUID().uuidString + UUID().uuidString
        }
        return Data(bytes).base64EncodedString()
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
