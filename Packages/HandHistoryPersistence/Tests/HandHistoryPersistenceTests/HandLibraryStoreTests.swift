import Foundation
import HandHistory
import Testing

@testable import HandHistoryPersistence

/// A fresh temporary directory per test, removed afterward, so no test sees
/// another's files and none touches a real library.
private func withTemporaryStore(
    _ body: (FileHandLibraryStore) async throws -> Void
) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("HandLibraryStoreTests-\(UUID().uuidString)", isDirectory: true)
    let store = try FileHandLibraryStore(directory: root)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(store)
}

@Suite("个人牌谱库存储")
struct HandLibraryStoreTests {
    // T7 covers:1 — accept then retrieve returns a field-for-field equal hand,
    // byte-identical raw text, and the same identity.
    @Test("采纳后取回与采纳者逐字段相等")
    func acceptThenRetrieveEqualsAccepted() async throws {
        try await withTemporaryStore { store in
            let a = try SampleHands.handA()

            // Self-check: the library is empty before accept and holds exactly
            // one hand after, so a passing equality below is not vacuous.
            #expect(try await store.hands().isEmpty)

            try await store.accept(a)

            let stored = try await store.hands()
            #expect(stored.count == 1)

            let retrieved = try #require(try await store.hand(identity: a.source.identity))
            #expect(retrieved == a)
            #expect(retrieved.source.rawText == a.source.rawText)
            #expect(Array(retrieved.source.rawText.utf8) == Array(a.source.rawText.utf8))
            #expect(retrieved.source.identity == a.source.identity)
            #expect(retrieved.source.identity == HandSource(rawText: a.source.rawText).identity)
        }
    }

    // T8 covers:1 — re-accepting the same identity adds a version rather than
    // overwriting; version 1 stays byte-identical to what was first stored.
    @Test("重采纳保留旧版本")
    func reAcceptRetainsOldVersion() async throws {
        try await withTemporaryStore { store in
            let a = try SampleHands.handA()

            try await store.accept(a)
            #expect(try await store.versions(identity: a.source.identity) == [1])

            let firstVersionBytes = try await store.version(identity: a.source.identity, 1)
                .map { try $0.canonicalJSON() }
            #expect(firstVersionBytes != nil)

            try await store.accept(a)
            #expect(try await store.versions(identity: a.source.identity) == [1, 2])

            // Version 1 must be untouched by the second accept.
            let firstAgain = try #require(try await store.version(identity: a.source.identity, 1))
            #expect(try firstAgain.canonicalJSON() == firstVersionBytes)

            // The latest reflects the newest version.
            #expect(try await store.hand(identity: a.source.identity) == a)
        }
    }

    // T8 covers:2 — deleting one identity leaves the other and its raw text
    // untouched; the deleted identity and its versions are gone.
    @Test("删除一手不影响其余")
    func deleteOneLeavesTheRest() async throws {
        try await withTemporaryStore { store in
            let a = try SampleHands.handA()
            let b = try SampleHands.handB()
            #expect(a.source.identity != b.source.identity)

            try await store.accept(a)
            try await store.accept(b)
            #expect(try await store.hands().count == 2)

            try await store.delete(identity: a.source.identity)

            let remaining = try await store.hands()
            #expect(remaining.count == 1)
            let onlyB = try #require(remaining.first)
            #expect(onlyB == b)
            #expect(onlyB.source.rawText == b.source.rawText)

            // A and its versions are gone.
            #expect(try await store.hand(identity: a.source.identity) == nil)
            #expect(try await store.versions(identity: a.source.identity).isEmpty)

            // B is still fully retrievable by identity.
            #expect(try await store.hand(identity: b.source.identity) == b)
        }
    }
}
