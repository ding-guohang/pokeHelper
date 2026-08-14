import Foundation
import StrategyContent

/// Loads the bundled HU push/fold packs by effective depth.
///
/// These packs are `reviewed` (named human sign-off, content version
/// 2026.08.14-hu-pf.reviewed.1) and ship in every channel, so `availableDepths()`
/// is populated in store too. Bundled bytes are still not trusted: every pack
/// goes through the same checksum + semantic validation as `BundledContentLoader`.
struct TournamentPushFoldLoader {
    static let minDepth = 1
    static let maxDepth = 20

    struct Resource {
        let data: Data
        let recordedSHA256: String?
    }

    private let resource: (Int) -> Resource?

    init(resource: @escaping (Int) -> Resource?) {
        self.resource = resource
    }

    init(bundle: Bundle) {
        self.init { depth in
            let name = String(format: "tourn-hu-chip-ev-noante-%02dbb", depth)
            guard let url = bundle.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url)
            else {
                return nil
            }
            let checksum = bundle
                .url(forResource: name, withExtension: "sha256")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return Resource(data: data, recordedSHA256: checksum)
        }
    }

    /// Depths whose packs are present in this build, ascending. Empty in the
    /// store channel.
    func availableDepths() -> [Int] {
        (Self.minDepth...Self.maxDepth).filter { resource($0) != nil }
    }

    /// Loads and validates the pack for a depth, or nil if it is not bundled.
    func loadPack(depth: Int) throws -> StrategyPack? {
        guard let found = resource(depth) else { return nil }
        return try StrategyPackLoader().load(
            data: found.data,
            expectedSHA256: found.recordedSHA256
        )
    }
}
