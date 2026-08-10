import Foundation
import StrategyContent
@testable import PokerCoach

/// Packs for the update tests, built by re-encoding the bundled core content at
/// a different version.
///
/// Reusing real shipped content rather than a hand-written blob keeps these
/// tests honest about what the loader will actually be asked to parse.
enum ContentUpdateFixture {
    enum FixtureError: Error {
        case bundledContentMissing
    }

    static func pack(contentVersion: String) throws -> StrategyPack {
        try StrategyPackLoader().load(
            data: try encodedPack(contentVersion: contentVersion),
            expectedSHA256: nil
        )
    }

    static func encodedPack(contentVersion: String) throws -> Data {
        guard let url = Bundle.main.url(
            forResource: "CoreStrategyPack",
            withExtension: "json"
        ) else {
            throw FixtureError.bundledContentMissing
        }

        var root = try JSONSerialization.jsonObject(
            with: try Data(contentsOf: url)
        ) as! [String: Any]
        var manifest = root["manifest"] as! [String: Any]
        manifest["contentVersion"] = contentVersion
        root["manifest"] = manifest

        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.sortedKeys]
        )
    }
}
