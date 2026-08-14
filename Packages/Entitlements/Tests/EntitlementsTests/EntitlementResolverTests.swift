import Foundation
import Testing
@testable import Entitlements

private let now = Date(timeIntervalSince1970: 1_000_000)
private let later = Date(timeIntervalSince1970: 1_001_000)

private let core: FeatureKey = "cash-decision-training"
private let premium: FeatureKey = "cloud-sync"

@Suite("权限解析器按策略门控")
struct EntitlementResolverTests {
    @Test("未受限功能对任何状态恒解锁")
    func ungatedFeatureAlwaysUnlocked() {
        let resolver = EntitlementResolver(policy: EntitlementPolicy(gatedFeatures: [premium]))
        for status: EntitlementStatus in [.free, .expired, .subscribed(until: later), .inGracePeriod(until: later)] {
            #expect(resolver.isUnlocked(core, status: status, at: now))
        }
    }

    @Test("受限功能随状态开合")
    func gatedFeatureFollowsStatus() {
        let resolver = EntitlementResolver(policy: EntitlementPolicy(gatedFeatures: [premium]))
        #expect(resolver.isUnlocked(premium, status: .subscribed(until: later), at: now))
        #expect(resolver.isUnlocked(premium, status: .inGracePeriod(until: later), at: now))
        #expect(!resolver.isUnlocked(premium, status: .free, at: now))
        #expect(!resolver.isUnlocked(premium, status: .expired, at: now))
    }

    @Test("空策略保持现状：一切解锁")
    func emptyPolicyUnlocksEverything() {
        let resolver = EntitlementResolver(policy: .everythingFree)
        #expect(resolver.isUnlocked(core, status: .free, at: now))
        #expect(resolver.isUnlocked(premium, status: .free, at: now))
        #expect(resolver.access(to: premium, status: .expired, at: now) == .unlocked)
    }
}
