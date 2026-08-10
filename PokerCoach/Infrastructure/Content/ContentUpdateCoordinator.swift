import Foundation
import StrategyContent

/// A candidate content pack offered by some source.
struct ContentUpdateOffer: Sendable, Equatable {
    let data: Data
    /// The checksum the source claims for `data`. Verified before decoding.
    let declaredSHA256: String
    let contentVersion: String
}

/// Where a candidate content pack comes from.
///
/// M1C ships bundled content only. The HTTPS endpoint that would back a real
/// implementation is deliberately out of scope: it has nothing to serve until a
/// second content version exists. The client-side rules — verify the checksum,
/// refuse anything not strictly newer, keep serving the current pack on refusal
/// — are implemented and tested here so adding the endpoint later is an
/// increment rather than a redesign.
protocol ContentUpdateSource: Sendable {
    func fetchCandidate() async throws -> ContentUpdateOffer?
}

/// The source used while content ships only inside the app bundle.
///
/// Offering nothing is the truthful answer today, and it keeps the update path
/// live rather than dormant: the coordinator runs on every launch, so the day
/// an endpoint exists only this type is replaced.
struct BundledOnlyContentSource: ContentUpdateSource {
    func fetchCandidate() async throws -> ContentUpdateOffer? { nil }
}

enum ContentUpdateOutcome: Sendable, Equatable {
    case adopted(contentVersion: String)
    case ignored(IgnoreReason)
    case rejected(RejectReason)
    case noCandidate

    enum IgnoreReason: Sendable, Equatable {
        case notNewer
    }

    enum RejectReason: Sendable, Equatable {
        case checksumMismatch
        case invalidPack
        case unparseableVersion
    }
}

/// Decides whether a candidate pack replaces the one in use.
///
/// Refusal never degrades to "no content": training continues against whatever
/// was already validated.
@MainActor
final class ContentUpdateCoordinator {
    private(set) var currentPack: StrategyPack
    private(set) var availability: StrategyContentAvailability
    private let source: any ContentUpdateSource

    init(
        current: StrategyPack,
        availability: StrategyContentAvailability,
        source: any ContentUpdateSource
    ) {
        currentPack = current
        self.availability = availability
        self.source = source
    }

    func checkForUpdate() async throws -> ContentUpdateOutcome {
        guard let offer = try await source.fetchCandidate() else {
            return .noCandidate
        }

        guard let candidateVersion = ContentVersion(offer.contentVersion),
              let installedVersion = ContentVersion(currentPack.manifest.contentVersion)
        else {
            return .rejected(.unparseableVersion)
        }
        guard candidateVersion > installedVersion else {
            return .ignored(.notNewer)
        }

        let pack: StrategyPack
        do {
            pack = try StrategyPackLoader().load(
                data: offer.data,
                expectedSHA256: offer.declaredSHA256
            )
        } catch StrategyPackLoadingError.checksumMismatch {
            return .rejected(.checksumMismatch)
        } catch {
            return .rejected(.invalidPack)
        }

        // Retired content is never trained against. The bundled loader already
        // filters it out; adopting it here would install a pack that reports
        // "no content" and halts training.
        guard pack.manifest.reviewStatus != .retired else {
            return .rejected(.invalidPack)
        }

        currentPack = pack
        availability = Self.availability(
            for: pack.manifest.reviewStatus,
            origin: pack.manifest.origin
        )
        return .adopted(contentVersion: pack.manifest.contentVersion)
    }

    private static func availability(
        for status: ReviewStatus,
        origin: ContentOrigin
    ) -> StrategyContentAvailability {
        if origin == .generativeModel, status == .reviewed {
            return .modelAuthoredContentAvailable
        }

        return switch status {
        case .reviewed: .reviewedContentAvailable
        case .unverifiedDraft: .unverifiedContentAvailable
        case .testFixture: .developmentFixtureAvailable
        // Unreachable: refused above.
        case .retired: .reviewedContentUnavailable
        }
    }
}

/// A dotted numeric content version.
///
/// Compared component by component, never as a string: "2026.9.1" and
/// "2026.09.01" name the same release but sort differently as text, and
/// "2026.10.01" sorts before "2026.9.01".
struct ContentVersion: Comparable, Equatable {
    let components: [Int]

    init?(_ text: String) {
        let parsed = text.split(separator: ".").map { Int($0) }
        guard !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) else {
            return nil
        }
        components = parsed.compactMap { $0 }
    }

    static func < (lhs: ContentVersion, rhs: ContentVersion) -> Bool {
        for index in 0 ..< max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}
