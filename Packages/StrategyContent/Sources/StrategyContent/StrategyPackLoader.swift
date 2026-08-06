import CryptoKit
import Foundation

public struct StrategyPackLoader: Sendable {
    public init() {}

    public func load(data: Data, expectedSHA256: String?) throws -> StrategyPack {
        if let expectedSHA256 {
            let actualSHA256 = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()

            guard actualSHA256 == expectedSHA256 else {
                throw StrategyPackLoadingError.checksumMismatch
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let pack: StrategyPack
        do {
            pack = try decoder.decode(StrategyPack.self, from: data)
        } catch {
            throw StrategyPackLoadingError.decodingFailed
        }

        try StrategyPackValidator().validate(pack)
        return pack
    }
}
