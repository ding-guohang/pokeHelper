import Foundation

/// Persists the identifiers that outlive any single session: the installation
/// device ID, each profile's local user ID, and who claimed the anonymous
/// history.
///
/// These are identifiers, not credentials, so they live in a plain file inside
/// the app container rather than the Keychain.
///
/// The file logic is separate from the actor because app startup resolves the
/// anonymous profile synchronously, before any concurrency-aware component
/// exists. Both paths therefore share one implementation instead of keeping
/// two copies that could drift.
struct ProfileRecordFile: Sendable {
    private struct Record: Codable, Sendable {
        var deviceID: UUID
        var localUserIDs: [String: UUID]
        var anonymousClaimedBy: UUID?
        var lastActiveProfile: String?
    }

    private let directory: URL
    private let makeUUID: @Sendable () -> UUID

    init(directory: URL, makeUUID: @escaping @Sendable () -> UUID = UUID.init) {
        self.directory = directory
        self.makeUUID = makeUUID
    }

    func deviceID() throws -> UUID {
        try record().deviceID
    }

    func localUserID(for profile: ProfileID) throws -> UUID {
        var current = try record()
        if let existing = current.localUserIDs[profile.rawValue] {
            return existing
        }
        let generated = makeUUID()
        current.localUserIDs[profile.rawValue] = generated
        try save(current)
        return generated
    }

    /// Binds the anonymous history to a remote account.
    ///
    /// Returns false when somebody already claimed it. Anonymous history can be
    /// adopted exactly once; a second account signing in on the same
    /// installation starts from an empty profile instead of inheriting somebody
    /// else's hands.
    func claimAnonymous(by remoteUserID: UUID) throws -> Bool {
        var current = try record()
        guard current.anonymousClaimedBy == nil else {
            return false
        }

        let anonymousLocalID = try localUserID(for: .anonymous)
        current = try record()
        current.anonymousClaimedBy = remoteUserID
        // The claimed profile inherits the anonymous local user ID so events
        // written before and after the claim keep one consistent identity.
        current.localUserIDs[ProfileID(remoteUserID: remoteUserID).rawValue] = anonymousLocalID
        // Anonymous training after the claim belongs to nobody, so it starts
        // over with a fresh identity.
        current.localUserIDs[ProfileID.anonymous.rawValue] = nil
        try save(current)
        return true
    }

    func anonymousClaimant() throws -> UUID? {
        try record().anonymousClaimedBy
    }

    /// The profile the app was last using. Startup resolves this synchronously
    /// so a signed-in user reopens on their own data rather than flashing the
    /// anonymous profile first.
    func lastActiveProfile() throws -> ProfileID {
        guard let raw = try record().lastActiveProfile else {
            return .anonymous
        }
        return ProfileID(rawValue: raw)
    }

    func setLastActiveProfile(_ profile: ProfileID) throws {
        var current = try record()
        current.lastActiveProfile = profile.rawValue
        try save(current)
    }

    /// Seeds the anonymous profile with an M1A identity so migrated events keep
    /// matching the identifiers new events are written with.
    func adoptLegacyIdentity(_ identity: LocalIdentity) throws {
        var current = try record()
        guard current.localUserIDs[ProfileID.anonymous.rawValue] == nil else {
            return
        }
        current.deviceID = identity.deviceID
        current.localUserIDs[ProfileID.anonymous.rawValue] = identity.localUserID
        try save(current)
    }

    private func record() throws -> Record {
        if
            let data = try? Data(contentsOf: file),
            let decoded = try? JSONDecoder().decode(Record.self, from: data)
        {
            return decoded
        }
        let fresh = Record(
            deviceID: makeUUID(),
            localUserIDs: [:],
            anonymousClaimedBy: nil,
            lastActiveProfile: nil
        )
        try save(fresh)
        return fresh
    }

    private func save(_ record: Record) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try JSONEncoder().encode(record).write(to: file, options: .atomic)
    }

    private var file: URL {
        directory.appending(path: "profiles.json", directoryHint: .notDirectory)
    }
}

/// Serializes access to the profile record so concurrent sign-in and sign-out
/// cannot interleave a read-modify-write.
actor ProfileAssociationStore {
    private let records: ProfileRecordFile

    init(directory: URL, makeUUID: @escaping @Sendable () -> UUID = UUID.init) {
        records = ProfileRecordFile(directory: directory, makeUUID: makeUUID)
    }

    func deviceID() throws -> UUID {
        try records.deviceID()
    }

    func localUserID(for profile: ProfileID) throws -> UUID {
        try records.localUserID(for: profile)
    }

    func claimAnonymous(by remoteUserID: UUID) throws -> Bool {
        try records.claimAnonymous(by: remoteUserID)
    }

    func anonymousClaimant() throws -> UUID? {
        try records.anonymousClaimant()
    }

    func lastActiveProfile() throws -> ProfileID {
        try records.lastActiveProfile()
    }

    func setLastActiveProfile(_ profile: ProfileID) throws {
        try records.setLastActiveProfile(profile)
    }
}
