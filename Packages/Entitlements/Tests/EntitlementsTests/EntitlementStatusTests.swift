import Foundation
import Testing
@testable import Entitlements

/// Fixed instants so validity is deterministic and never reads a real clock.
private let now = Date(timeIntervalSince1970: 1_000_000)
private let earlier = Date(timeIntervalSince1970: 999_000)
private let later = Date(timeIntervalSince1970: 1_001_000)

@Suite("权限状态的到期判定")
struct EntitlementStatusTests {
    @Test("生效订阅在到期前有效")
    func subscribedBeforeExpiryIsValid() {
        #expect(EntitlementStatus.subscribed(until: later).isValid(at: now))
    }

    @Test("订阅到期时刻起失效")
    func subscribedAtOrAfterExpiryIsInvalid() {
        #expect(!EntitlementStatus.subscribed(until: now).isValid(at: now))
        #expect(!EntitlementStatus.subscribed(until: earlier).isValid(at: now))
    }

    @Test("宽限期内仍有效，期满失效")
    func gracePeriodValidUntilEnd() {
        #expect(EntitlementStatus.inGracePeriod(until: later).isValid(at: now))
        #expect(!EntitlementStatus.inGracePeriod(until: now).isValid(at: now))
    }

    @Test("free 与 expired 恒失效")
    func freeAndExpiredNeverValid() {
        #expect(!EntitlementStatus.free.isValid(at: now))
        #expect(!EntitlementStatus.expired.isValid(at: now))
    }
}
