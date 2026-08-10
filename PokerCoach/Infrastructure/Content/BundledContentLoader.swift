import Foundation
import StrategyContent

/// Loads the strategy content that shipped inside the app bundle.
///
/// Bundled content is not trusted input: it goes through the same checksum and
/// semantic validation as anything downloaded, because a resource can be
/// replaced in a repackaged build.
struct BundledContentLoader {
    enum LoadError: Error, Equatable {
        case noContentInBundle
        case invalid(packID: String, underlying: String)
    }

    struct LoadedContent {
        let pack: StrategyPack
        let availability: StrategyContentAvailability
        /// Review status of every pack found, keyed by pack ID. Review reads it
        /// to disclose the provenance of a history entry.
        let installedContent: [String: ReviewStatus]
    }

    /// Resource names, most trustworthy first. The order is also the preference
    /// order when several are present, which is how a dogfooding build that
    /// carries both ends up training against the reviewed pack.
    static let resourceNames = [
        "CoreStrategyPack",
        "UnverifiedStrategyPack",
        "DevStrategyPack",
    ]

    private let bundle: Bundle

    init(bundle: Bundle) {
        self.bundle = bundle
    }

    func loadPreferredPack() throws -> LoadedContent {
        var packs: [StrategyPack] = []

        for name in Self.resourceNames {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                continue
            }
            let data = try Data(contentsOf: url)
            do {
                packs.append(
                    try StrategyPackLoader().load(
                        data: data,
                        expectedSHA256: expectedChecksum(for: name)
                    )
                )
            } catch {
                // A bundled pack that fails validation is a build defect, not a
                // reason to fall through to a lesser pack: doing that would ship
                // unreviewed content in place of reviewed content that was
                // merely corrupted.
                throw LoadError.invalid(packID: name, underlying: "\(error)")
            }
        }

        guard let preferred = packs.min(by: {
            Self.trustRank($0.manifest.reviewStatus) < Self.trustRank($1.manifest.reviewStatus)
        }) else {
            throw LoadError.noContentInBundle
        }

        return LoadedContent(
            pack: preferred,
            availability: Self.availability(for: preferred.manifest.reviewStatus),
            installedContent: Dictionary(
                packs.map { ($0.manifest.id, $0.manifest.reviewStatus) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }

    /// Checksum recorded beside the pack at import time, when one shipped.
    private func expectedChecksum(for name: String) -> String? {
        guard let url = bundle.url(forResource: name, withExtension: "sha256"),
              let recorded = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }
        return recorded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trustRank(_ status: ReviewStatus) -> Int {
        switch status {
        case .reviewed: 0
        case .unverifiedDraft: 1
        case .testFixture: 2
        case .retired: 3
        }
    }

    private static func availability(
        for status: ReviewStatus
    ) -> StrategyContentAvailability {
        switch status {
        case .reviewed: .reviewedContentAvailable
        case .unverifiedDraft: .unverifiedContentAvailable
        case .testFixture: .developmentFixtureAvailable
        // Retired content is kept for history, never trained against.
        case .retired: .reviewedContentUnavailable
        }
    }
}
