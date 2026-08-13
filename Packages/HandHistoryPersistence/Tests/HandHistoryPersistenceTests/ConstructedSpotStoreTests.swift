import Foundation
import HandHistory
import PokerCore
import Testing

@testable import HandHistoryPersistence

/// A fresh temporary directory per test, removed afterward, so no test sees
/// another's files and none touches a real store.
private func withTemporaryStore(
    _ body: (FileConstructedSpotStore) async throws -> Void
) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ConstructedSpotStoreTests-\(UUID().uuidString)", isDirectory: true)
    let store = try FileConstructedSpotStore(directory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(store)
}

private enum SampleSpots {
    /// spot 甲: BTN, A5s, unopened, 100BB deep.
    static func jia() throws -> ConstructedSpot {
        try ConstructedSpot(
            heroSeatOffsetFromButton: 0,
            holeCardCodes: ["Ah", "5h"],
            facing: FacingAction(priorRaiseCount: 0),
            effectiveStackCentiBB: 10_000,
            action: .raise(to: BBAmount(centiBB: 300))
        )
    }

    /// spot 乙: CO, 72o, facing a single raise, 16BB short — a distinct identity.
    static func yi() throws -> ConstructedSpot {
        try ConstructedSpot(
            heroSeatOffsetFromButton: 5,
            holeCardCodes: ["7c", "2d"],
            facing: FacingAction(priorRaiseCount: 1),
            effectiveStackCentiBB: 1_600,
            action: .fold
        )
    }
}

@Suite("手动 spot 存储")
struct ConstructedSpotStoreTests {
    // T2 covers:1 — save then retrieve returns a field-for-field equal spot.
    @Test("保存后取回逐字段相等")
    func saveThenRetrieveEqualsSaved() async throws {
        try await withTemporaryStore { store in
            let jia = try SampleSpots.jia()

            // Self-check: the store is empty before save, so a passing equality
            // below is not vacuous.
            #expect(try await store.spots().isEmpty)

            try await store.save(jia)

            let stored = try await store.spots()
            #expect(stored.count == 1)

            let retrieved = try #require(try await store.spot(identity: jia.identity))
            #expect(retrieved == jia)
            #expect(retrieved.heroSeatOffsetFromButton == jia.heroSeatOffsetFromButton)
            #expect(retrieved.holeCards == jia.holeCards)
            #expect(retrieved.facing == jia.facing)
            #expect(retrieved.effectiveStackCentiBB == jia.effectiveStackCentiBB)
            #expect(retrieved.action == jia.action)
            #expect(retrieved.identity == jia.identity)
        }
    }

    // T2 covers:1 — re-saving the same identity adds a version rather than
    // overwriting; version 1 stays byte-identical to what was first stored.
    @Test("重存保留旧版本且字节不变")
    func reSaveRetainsOldVersionBytes() async throws {
        try await withTemporaryStore { store in
            let jia = try SampleSpots.jia()

            try await store.save(jia)
            #expect(try await store.versions(identity: jia.identity) == [1])

            let firstVersionBytes = try await store.version(identity: jia.identity, 1)
                .map { try $0.canonicalJSON() }
            #expect(firstVersionBytes != nil)

            try await store.save(jia)
            #expect(try await store.versions(identity: jia.identity) == [1, 2])

            // Version 1 must be untouched by the second save.
            let firstAgain = try #require(try await store.version(identity: jia.identity, 1))
            #expect(try firstAgain.canonicalJSON() == firstVersionBytes)

            // The latest reflects the newest version.
            #expect(try await store.spot(identity: jia.identity) == jia)
        }
    }

    // T2 covers:1 — deleting one identity leaves the other intact; the deleted
    // identity and its versions are gone.
    @Test("删除一个不影响其余")
    func deleteOneLeavesTheRest() async throws {
        try await withTemporaryStore { store in
            let jia = try SampleSpots.jia()
            let yi = try SampleSpots.yi()
            #expect(jia.identity != yi.identity)

            try await store.save(jia)
            try await store.save(yi)
            #expect(try await store.spots().count == 2)

            try await store.delete(identity: jia.identity)

            let remaining = try await store.spots()
            #expect(remaining.count == 1)
            let onlyYi = try #require(remaining.first)
            #expect(onlyYi == yi)
            #expect(onlyYi.heroSeatOffsetFromButton == yi.heroSeatOffsetFromButton)
            #expect(onlyYi.holeCards == yi.holeCards)
            #expect(onlyYi.facing == yi.facing)
            #expect(onlyYi.effectiveStackCentiBB == yi.effectiveStackCentiBB)
            #expect(onlyYi.action == yi.action)

            // 甲 and its versions are gone.
            #expect(try await store.spot(identity: jia.identity) == nil)
            #expect(try await store.versions(identity: jia.identity).isEmpty)

            // 乙 is still fully retrievable by identity.
            #expect(try await store.spot(identity: yi.identity) == yi)
        }
    }
}
