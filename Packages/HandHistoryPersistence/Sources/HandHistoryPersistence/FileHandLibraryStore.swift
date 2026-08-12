import Foundation
import HandHistory

public enum HandLibraryStoreError: Error, Equatable {
    /// A version file that will not decode, with the identity and version it
    /// belongs to. Named rather than surfaced as a bare decode error so a
    /// corrupt library points at the hand it lost, not a thousand bytes of JSON.
    case corruptedVersion(identity: String, version: Int)
}

/// A personal library of imported hands on disk: one directory per hand
/// identity (the SHA-256 of its normalized text), holding an append-only set of
/// version files `v1.json`, `v2.json`, …
///
/// Versions are added, never rewritten. Re-accepting the same identity writes a
/// new file with the next number and leaves the earlier ones exactly as they
/// were — a store that overwrote the newest into the same file would satisfy a
/// weaker reading of "keeps old versions" and lose the original. Deleting an
/// identity removes only that directory, so the rest of the library is
/// untouched. The dependency runs persistence -> `HandHistory` and never back;
/// nothing here can reach a `TrainingEvent`.
public actor FileHandLibraryStore {
    private let root: URL

    public init(directory: URL) throws {
        root = directory.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    /// Stores `hand` as a new version under its identity.
    ///
    /// Never overwrites: the next version number is one past the highest already
    /// present (1 for a hand never seen before), so an earlier import of the
    /// same text stays byte-for-byte on disk.
    public func accept(_ hand: ObservedHand) throws {
        let identity = hand.source.identity
        let directory = identityDirectory(identity)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let next = (try versions(identity: identity).last ?? 0) + 1
        // The canonical encoding is what the golden fixture and cross-process
        // comparison use, so the file on disk is the same bytes.
        let data = try hand.canonicalJSON()
        try data.write(to: versionURL(identity, next), options: .atomic)
    }

    /// The latest version of every stored identity, ordered by identity string
    /// for a stable listing.
    public func hands() throws -> [ObservedHand] {
        try storedIdentities().compactMap { try hand(identity: $0) }
    }

    /// The latest version stored for `identity`, or nil if none is.
    public func hand(identity: String) throws -> ObservedHand? {
        guard let latest = try versions(identity: identity).last else { return nil }
        return try version(identity: identity, latest)
    }

    /// Ascending version numbers present for `identity`; empty if none.
    public func versions(identity: String) throws -> [Int] {
        let directory = identityDirectory(identity)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return entries
            .compactMap { versionNumber(of: $0.lastPathComponent) }
            .sorted()
    }

    /// A specific version of `identity`, or nil if that version is absent.
    public func version(identity: String, _ n: Int) throws -> ObservedHand? {
        let url = versionURL(identity, n)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(ObservedHand.self, from: data)
        } catch {
            throw HandLibraryStoreError.corruptedVersion(identity: identity, version: n)
        }
    }

    /// Removes `identity` and all of its versions. Other identities are
    /// untouched.
    public func delete(identity: String) throws {
        let directory = identityDirectory(identity)
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else {
            return
        }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: - Layout

    private func storedIdentities() throws -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map { $0.lastPathComponent }
            .sorted()
    }

    private func identityDirectory(_ identity: String) -> URL {
        root.appending(path: identity, directoryHint: .isDirectory)
    }

    private func versionURL(_ identity: String, _ n: Int) -> URL {
        identityDirectory(identity).appending(path: "v\(n).json", directoryHint: .notDirectory)
    }

    /// The number N in a "vN.json" file name, or nil for anything else.
    private func versionNumber(of name: String) -> Int? {
        guard name.hasPrefix("v"), name.hasSuffix(".json") else { return nil }
        let middle = name.dropFirst().dropLast(".json".count)
        return Int(middle)
    }
}
