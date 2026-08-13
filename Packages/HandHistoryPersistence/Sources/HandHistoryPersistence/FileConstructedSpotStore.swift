import Foundation
import HandHistory

public enum ConstructedSpotStoreError: Error, Equatable {
    /// A version file that will not decode, with the identity and version it
    /// belongs to. Named rather than surfaced as a bare decode error so a corrupt
    /// store points at the spot it lost, not a wall of JSON.
    case corruptedVersion(identity: String, version: Int)
}

/// Hand-built spots on disk: one directory per spot identity (the SHA-256 of its
/// canonical JSON), holding an append-only set of version files `v1.json`,
/// `v2.json`, …
///
/// Mirrors `FileHandLibraryStore`. Versions are added, never rewritten: saving
/// the same identity again writes a new file with the next number and leaves the
/// earlier ones byte-for-byte, so a store that overwrote the newest into the same
/// file would satisfy a weaker reading of "keeps old versions" and lose the
/// original. Deleting an identity removes only that directory, so the rest is
/// untouched. The dependency runs persistence -> `HandHistory` and never back;
/// nothing here can reach a `TrainingEvent`.
public actor FileConstructedSpotStore {
    private let root: URL

    public init(directory: URL) throws {
        root = directory.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    /// Stores `spot` as a new version under its identity.
    ///
    /// Never overwrites: the next version number is one past the highest already
    /// present (1 for a spot never seen before), so an earlier save of the same
    /// spot stays byte-for-byte on disk.
    public func save(_ spot: ConstructedSpot) throws {
        let identity = spot.identity
        let directory = identityDirectory(identity)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let next = (try versions(identity: identity).last ?? 0) + 1
        // The canonical encoding is what identity is derived from, so the file on
        // disk is those exact bytes.
        let data = try spot.canonicalJSON()
        try data.write(to: versionURL(identity, next), options: .atomic)
    }

    /// The latest version of every stored identity, ordered by identity string
    /// for a stable listing.
    public func spots() throws -> [ConstructedSpot] {
        try storedIdentities().compactMap { try spot(identity: $0) }
    }

    /// The latest version stored for `identity`, or nil if none is.
    public func spot(identity: String) throws -> ConstructedSpot? {
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
    public func version(identity: String, _ n: Int) throws -> ConstructedSpot? {
        let url = versionURL(identity, n)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(ConstructedSpot.self, from: data)
        } catch {
            throw ConstructedSpotStoreError.corruptedVersion(identity: identity, version: n)
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
