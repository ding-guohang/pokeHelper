/// An opaque identifier for a gateable feature.
///
/// Deliberately a string key rather than an enum of the app's features: the
/// mechanism must not couple to the app's feature taxonomy, and *which* features
/// are premium is a product decision recorded in the policy — not a fact about
/// this type.
public struct FeatureKey: Sendable, Hashable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension FeatureKey: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

/// The set of feature keys that require a valid entitlement.
///
/// The empty policy gates nothing — every feature is free — which is the default
/// and keeps behaviour identical to a build with no monetization at all. The
/// north-star invariant (the core decision-training learning loop is never
/// paywalled) is a property of how the product layer *constructs* a policy, not
/// of this mechanism: this type only records which keys are gated.
public struct EntitlementPolicy: Sendable, Equatable {
    public let gatedFeatures: Set<FeatureKey>

    public init(gatedFeatures: Set<FeatureKey> = []) {
        self.gatedFeatures = gatedFeatures
    }

    /// The default: nothing is gated, so the app behaves exactly as it does
    /// today until a monetization policy is deliberately chosen.
    public static let everythingFree = EntitlementPolicy()

    /// Whether `feature` requires a valid entitlement under this policy.
    public func gates(_ feature: FeatureKey) -> Bool {
        gatedFeatures.contains(feature)
    }
}
