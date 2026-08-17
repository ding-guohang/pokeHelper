import Foundation
import StrategyContent

/// Loads the bundled `reviewed` river packs listed in `river-packs-index.json`.
///
/// Unlike the push/fold loader (which addresses packs by depth), river packs are
/// addressed by board id from a small bundled index, so the content set can grow
/// without recompiling. These packs are `reviewed` (named human sign-off), so
/// they ship in every channel including store. Bundled bytes are not trusted:
/// every pack goes through the same checksum + semantic validation as
/// `BundledContentLoader`.
struct RiverTrainerLoader {
    struct Resource {
        let data: Data
        let recordedSHA256: String?
    }

    private let indexProvider: () -> [String]
    private let resource: (String) -> Resource?

    init(index: @escaping () -> [String], resource: @escaping (String) -> Resource?) {
        self.indexProvider = index
        self.resource = resource
    }

    init(bundle: Bundle) {
        self.init(
            index: {
                guard let url = bundle.url(forResource: "river-packs-index", withExtension: "json"),
                      let data = try? Data(contentsOf: url),
                      let decoded = try? JSONDecoder().decode(RiverPackIndex.self, from: data)
                else {
                    return []
                }
                return decoded.packs
            },
            resource: { boardID in
                guard let url = bundle.url(forResource: boardID, withExtension: "json"),
                      let data = try? Data(contentsOf: url)
                else {
                    return nil
                }
                let checksum = bundle
                    .url(forResource: boardID, withExtension: "sha256")
                    .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                return Resource(data: data, recordedSHA256: checksum)
            }
        )
    }

    /// Board ids whose packs are present in this build, in index order.
    func availableBoards() -> [String] {
        indexProvider().filter { resource($0) != nil }
    }

    /// Loads and validates the pack for a board id, or nil if it is not bundled.
    func loadPack(boardID: String) throws -> StrategyPack? {
        guard let found = resource(boardID) else { return nil }
        return try StrategyPackLoader().load(
            data: found.data,
            expectedSHA256: found.recordedSHA256
        )
    }
}

private struct RiverPackIndex: Decodable {
    let packs: [String]
}
