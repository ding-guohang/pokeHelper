import Foundation

struct LocalIdentity: Equatable, Sendable {
    let localUserID: UUID
    let deviceID: UUID

    static let preview = LocalIdentity(
        localUserID: UUID(
            uuidString: "10000000-0000-0000-0000-000000000001"
        )!,
        deviceID: UUID(
            uuidString: "20000000-0000-0000-0000-000000000001"
        )!
    )
}

@MainActor
final class LocalIdentityStore {
    private enum Key {
        static let localUserID =
            "com.porkhelper.pokercoach.identity.local-user-id"
        static let deviceID =
            "com.porkhelper.pokercoach.identity.device-id"
    }

    private let userDefaults: UserDefaults
    private let makeUUID: @MainActor () -> UUID

    init(
        userDefaults: UserDefaults = .standard,
        makeUUID: @escaping @MainActor () -> UUID = UUID.init
    ) {
        self.userDefaults = userDefaults
        self.makeUUID = makeUUID
    }

    func loadOrCreate() -> LocalIdentity {
        LocalIdentity(
            localUserID: loadOrCreateUUID(forKey: Key.localUserID),
            deviceID: loadOrCreateUUID(forKey: Key.deviceID)
        )
    }

    /// The identity an M1A installation left in UserDefaults, if any.
    ///
    /// M1B keeps identities in the profile record instead, so this is read only
    /// once during migration. It never creates an identity, because doing so
    /// would make a fresh install look like an upgrade.
    func storedIdentity() -> LocalIdentity? {
        guard
            let storedUser = userDefaults.string(forKey: Key.localUserID),
            let localUserID = UUID(uuidString: storedUser),
            let storedDevice = userDefaults.string(forKey: Key.deviceID),
            let deviceID = UUID(uuidString: storedDevice)
        else {
            return nil
        }
        return LocalIdentity(localUserID: localUserID, deviceID: deviceID)
    }

    private func loadOrCreateUUID(forKey key: String) -> UUID {
        if
            let storedValue = userDefaults.string(forKey: key),
            let storedID = UUID(uuidString: storedValue)
        {
            return storedID
        }

        let generatedID = makeUUID()
        userDefaults.set(generatedID.uuidString, forKey: key)
        return generatedID
    }
}
