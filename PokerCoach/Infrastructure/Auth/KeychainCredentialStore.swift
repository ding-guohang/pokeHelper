import Foundation
import Security

/// Credential store backed by a single secure vault item.
///
/// The active session and the pending-revocation slot live in one encoded
/// payload so moving a refresh token between them is a single write. Splitting
/// them across two items would make the move non-atomic: a crash in between
/// could leave a logged-out token still usable.
struct KeychainCredentialStore: CredentialStore {
    private struct Payload: Codable, Sendable {
        var active: StoredSession?
        var pendingRevocation: PendingSessionRevocation?

        var isEmpty: Bool {
            active == nil && pendingRevocation == nil
        }
    }

    private let vault: any SecureVault

    init(vault: any SecureVault) {
        self.vault = vault
    }

    func loadActive() async throws -> StoredSession? {
        try await load().active
    }

    func saveActive(_ session: StoredSession) async throws {
        var payload = try await load()
        payload.active = session
        try await store(payload)
    }

    func replaceActive(
        expectedRefreshToken: String,
        with session: StoredSession
    ) async throws {
        var payload = try await load()
        guard let active = payload.active else {
            throw CredentialStoreError.noActiveSession
        }
        guard active.refreshToken == expectedRefreshToken else {
            throw CredentialStoreError.staleRefreshToken
        }
        payload.active = session
        try await store(payload)
    }

    func clearActive() async throws {
        var payload = try await load()
        payload.active = nil
        try await store(payload)
    }

    func moveRefreshToPendingRevocation() async throws {
        var payload = try await load()
        guard let active = payload.active else {
            return
        }
        payload.pendingRevocation = PendingSessionRevocation(
            refreshToken: active.refreshToken,
            userID: active.userID
        )
        payload.active = nil
        try await store(payload)
    }

    func loadPendingRevocation() async throws -> PendingSessionRevocation? {
        try await load().pendingRevocation
    }

    func clearPendingRevocation() async throws {
        var payload = try await load()
        payload.pendingRevocation = nil
        try await store(payload)
    }

    private func load() async throws -> Payload {
        guard let data = try await readVault() else {
            return Payload()
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            // Unreadable credential material is treated as absent rather than
            // fatal: the user can sign in again, and training is unaffected.
            return Payload()
        }
        return payload
    }

    private func store(_ payload: Payload) async throws {
        if payload.isEmpty {
            do {
                try await vault.delete()
            } catch {
                throw CredentialStoreError.unavailable
            }
            return
        }
        do {
            try await vault.write(try JSONEncoder().encode(payload))
        } catch {
            throw CredentialStoreError.unavailable
        }
    }

    private func readVault() async throws -> Data? {
        do {
            return try await vault.read()
        } catch {
            throw CredentialStoreError.unavailable
        }
    }
}

/// Security-framework vault. The individual `SecItem` calls are injected so
/// tests can drive success and failure paths without touching the real
/// Keychain, which is unavailable in some CI environments.
struct KeychainVault: SecureVault {
    struct Operations: Sendable {
        var copyMatching: @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
        var add: @Sendable (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
        var update: @Sendable (CFDictionary, CFDictionary) -> OSStatus
        var delete: @Sendable (CFDictionary) -> OSStatus

        static let system = Operations(
            copyMatching: { query, result in SecItemCopyMatching(query, result) },
            add: { attributes, result in SecItemAdd(attributes, result) },
            update: { query, attributes in SecItemUpdate(query, attributes) },
            delete: { query in SecItemDelete(query) }
        )
    }

    private let service: String
    private let account: String
    private let operations: Operations

    init(
        service: String = "com.porkhelper.pokercoach.account",
        account: String = "active-session",
        operations: Operations = .system
    ) {
        self.service = service
        self.account = account
        self.operations = operations
    }

    func read() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = operations.copyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw CredentialStoreError.unavailable
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.unavailable
        }
    }

    func write(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = operations.update(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.unavailable
        }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard operations.add(insert as CFDictionary, nil) == errSecSuccess else {
            throw CredentialStoreError.unavailable
        }
    }

    func delete() throws {
        let status = operations.delete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unavailable
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
