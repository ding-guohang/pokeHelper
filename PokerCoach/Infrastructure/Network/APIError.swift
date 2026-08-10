import Foundation

/// Typed transport failures. Every case carries Chinese recovery text so the
/// UI never has to invent a message, and none of them names a specific account
/// state — the server deliberately keeps those indistinguishable.
enum APIError: Error, Equatable, Sendable {
    case offline
    case timedOut
    case unauthorized
    case reauthenticationRequired
    case identityConflict
    case validationFailed
    case rateLimited(retryAfter: TimeInterval)
    /// The batch was well formed but too big. The recovery is to split it, not
    /// to change its content.
    case batchTooLarge
    case server(status: Int)
    case malformedResponse

    var recoverySuggestion: String {
        switch self {
        case .offline:
            "当前网络不可用，训练仍可离线继续，联网后会自动同步。"
        case .timedOut:
            "网络响应超时，请稍后重试。"
        case .unauthorized:
            "邮箱或密码不正确，请重新输入。"
        case .reauthenticationRequired:
            "该操作需要重新验证身份，请再次登录后继续。"
        case .identityConflict:
            "该 Apple 账号已绑定到另一个账号，无法重复绑定。"
        case .validationFailed:
            "提交的内容不符合要求，请检查后重试。"
        case let .rateLimited(retryAfter):
            "尝试过于频繁，请在 \(Int(retryAfter.rounded(.up))) 秒后重试。"
        case .batchTooLarge:
            "本次同步的数据量过大，正在自动拆分后重试。"
        case .server:
            "服务暂时不可用，请稍后重试。"
        case .malformedResponse:
            "服务返回了无法识别的内容，请稍后重试。"
        }
    }
}

extension APIError {
    /// True when the server judged the request itself unacceptable, so
    /// resending identical bytes cannot succeed. Transport failures and 5xx
    /// are excluded: those are worth retrying unchanged.
    var isServerRefusal: Bool {
        switch self {
        case .validationFailed, .identityConflict:
            true
        case .offline, .timedOut, .unauthorized, .reauthenticationRequired,
             .rateLimited, .server, .malformedResponse, .batchTooLarge:
            // batchTooLarge is excluded on purpose: the same events can still
            // be delivered in smaller batches, so quarantining them would
            // discard data the server never refused on its merits.
            false
        }
    }
}
