import Foundation

/// Whether a feature is available to the user.
public enum FeatureAccess: Sendable, Equatable {
    case unlocked
    case locked
}

/// Resolves whether a feature is unlocked, given an entitlement status and a
/// policy. Pure and deterministic — no clock of its own, no I/O.
///
/// A feature the policy does not gate is always unlocked, regardless of status;
/// a gated feature is unlocked only when the status is valid at the supplied
/// time. With `EntitlementPolicy.everythingFree` every feature is unlocked, so
/// wiring the resolver in ahead of a monetization decision changes nothing.
public struct EntitlementResolver: Sendable {
    public let policy: EntitlementPolicy

    public init(policy: EntitlementPolicy) {
        self.policy = policy
    }

    public func access(
        to feature: FeatureKey,
        status: EntitlementStatus,
        at now: Date
    ) -> FeatureAccess {
        guard policy.gates(feature) else { return .unlocked }
        return status.isValid(at: now) ? .unlocked : .locked
    }

    public func isUnlocked(
        _ feature: FeatureKey,
        status: EntitlementStatus,
        at now: Date
    ) -> Bool {
        access(to: feature, status: status, at: now) == .unlocked
    }
}
