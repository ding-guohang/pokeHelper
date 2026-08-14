import Foundation

/// A user's premium-access entitlement, as pure domain state.
///
/// This models only the *state* and its time-based validity. Where the state
/// comes from — a StoreKit transaction, a receipt, a server claim — is an
/// infrastructure concern deliberately kept out of this package: the type has no
/// dependency on StoreKit, the network, or persistence, so it can be exercised
/// entirely with fixed dates.
public enum EntitlementStatus: Sendable, Equatable {
    /// No premium entitlement.
    case free
    /// An active subscription valid until `until`.
    case subscribed(until: Date)
    /// A lapsed subscription inside its billing-retry grace window, valid until
    /// `until`. Access is preserved during grace so a failed renewal does not
    /// immediately revoke a paying user.
    case inGracePeriod(until: Date)
    /// A subscription that has ended.
    case expired

    /// Whether this status grants premium access at `now`.
    ///
    /// `subscribed` and `inGracePeriod` grant access strictly before their
    /// `until` instant; `free` and `expired` never grant access.
    public func isValid(at now: Date) -> Bool {
        switch self {
        case .free, .expired:
            false
        case let .subscribed(until), let .inGracePeriod(until):
            now < until
        }
    }
}
