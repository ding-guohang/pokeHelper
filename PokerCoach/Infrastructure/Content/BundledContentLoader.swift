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
        case invalid(packID: String, reason: InvalidReason)

        /// Why a bundled pack was rejected, kept as the error the check that
        /// rejected it actually threw.
        ///
        /// The three sources are different build defects and read differently:
        /// a checksum mismatch means the bytes were replaced after import, a
        /// decode failure means the schema drifted, and a validation failure
        /// names the scenario and the number that is wrong. Rendering them to
        /// prose at the throw site loses all of that, and leaves callers and
        /// tests matching on substrings of a message.
        enum InvalidReason: Error, Equatable {
            case loading(StrategyPackLoadingError)
            case validation(StrategyPackValidationError)
            /// A pack rejected by something other than the loader's own two
            /// error types. Preserved as text because there is nothing typed
            /// left to preserve, not as the default path.
            case unrecognized(String)
        }
    }

    struct LoadedContent {
        let pack: StrategyPack
        let availability: StrategyContentAvailability
        /// Review status of every pack found, keyed by pack ID. Review reads it
        /// to disclose the provenance of a history entry.
        let installedContent: [String: (ReviewStatus, ContentOrigin)]
    }

    /// Resource names, most trustworthy first. The order is also the preference
    /// order when several are present, which is how a dogfooding build that
    /// carries both ends up training against the reviewed pack.
    static let resourceNames = [
        "CoreStrategyPack",
        "UnverifiedStrategyPack",
        "DevStrategyPack",
    ]

    /// One bundled resource: its bytes and the digest recorded beside it.
    struct Resource {
        let name: String
        let data: Data
        let recordedSHA256: String?
    }

    /// Resource lookup, injected rather than reading a Bundle directly.
    ///
    /// A loader that can only read `Bundle.main` cannot be tested against a
    /// corrupt pack, a retired pack, or an empty bundle — which left the
    /// "a corrupt reviewed pack must not fall through to a lesser one" branch,
    /// the safety-critical one, with no coverage at all.
    private let resource: (String) -> Resource?

    init(resource: @escaping (String) -> Resource?) {
        self.resource = resource
    }

    init(bundle: Bundle) {
        self.init { name in
            guard let url = bundle.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url)
            else {
                return nil
            }
            let checksum = bundle
                .url(forResource: name, withExtension: "sha256")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return Resource(name: name, data: data, recordedSHA256: checksum)
        }
    }

    func loadPreferredPack() throws -> LoadedContent {
        var packs: [StrategyPack] = []

        for name in Self.resourceNames {
            guard let found = resource(name) else {
                continue
            }
            do {
                packs.append(
                    try StrategyPackLoader().load(
                        data: found.data,
                        expectedSHA256: found.recordedSHA256
                    )
                )
            } catch let error as StrategyPackLoadingError {
                // A bundled pack that fails validation is a build defect, not a
                // reason to fall through to a lesser pack: doing that would ship
                // unreviewed content in place of reviewed content that was
                // merely corrupted.
                throw LoadError.invalid(packID: name, reason: .loading(error))
            } catch let error as StrategyPackValidationError {
                throw LoadError.invalid(packID: name, reason: .validation(error))
            } catch {
                throw LoadError.invalid(
                    packID: name,
                    reason: .unrecognized("\(error)")
                )
            }
        }

        // Retired content is kept for history and never trained against, so it
        // is not a candidate. Selecting it and then reporting "not trainable"
        // used to trip an assertion in the composition root and abort at
        // launch, when the no-content screen exists for exactly this case.
        guard let preferred = packs
            .filter({ $0.manifest.reviewStatus != .retired })
            .min(by: {
                Self.trustRank($0.manifest.reviewStatus)
                    < Self.trustRank($1.manifest.reviewStatus)
            })
        else {
            throw LoadError.noContentInBundle
        }

        return LoadedContent(
            pack: preferred,
            availability: Self.availability(
                for: preferred.manifest.reviewStatus,
                origin: preferred.manifest.origin
            ),
            installedContent: Dictionary(
                packs.map {
                    ($0.manifest.id, ($0.manifest.reviewStatus, $0.manifest.origin))
                },
                uniquingKeysWith: { first, _ in first }
            )
        )
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
        for status: ReviewStatus,
        origin: ContentOrigin
    ) -> StrategyContentAvailability {
        // Model-authored content is disclosed however thoroughly it was
        // reviewed: review establishes that someone checked, not that the
        // numbers came from a solver.
        if origin == .generativeModel, status == .reviewed {
            return .modelAuthoredContentAvailable
        }

        return switch status {
        case .reviewed: .reviewedContentAvailable
        case .unverifiedDraft: .unverifiedContentAvailable
        case .testFixture: .developmentFixtureAvailable
        // Unreachable: retired packs are filtered out before selection.
        case .retired: .reviewedContentUnavailable
        }
    }
}
