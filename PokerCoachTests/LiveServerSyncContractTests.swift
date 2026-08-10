import Foundation
import TrainingDomain
import XCTest
@testable import PokerCoach

/// Drives the production client types against a live Go service.
///
/// Every other suite substitutes one side: Go tests build Go requests, Swift
/// tests answer with Swift stubs. Both can be internally perfect while
/// disagreeing about the wire, and they were — an extra `appVersion` field, an
/// uppercase UUID, and a 204 decoded as a session all shipped with every gate
/// green. Nothing here is substituted except the clock.
///
/// Skipped unless `scripts/test-live-m1b.sh` has started a server and passed
/// its address in, so an ordinary unit-test run stays hermetic.
@MainActor
final class LiveServerSyncContractTests: XCTestCase {
    private var baseURL: URL!
    private var directories: [URL] = []

    /// Where the harness publishes the live server's address.
    ///
    /// A host file rather than an environment variable: xcodebuild only
    /// forwards TEST_RUNNER_-prefixed variables to UI-test runners, not to
    /// unit tests hosted in the app, and silently skipping every test is worse
    /// than not having them.
    static let addressFile = "/tmp/pokercoach-live-api-url"

    override func setUpWithError() throws {
        let raw = ProcessInfo.processInfo.environment["M1B_TEST_API_BASE_URL"]
            ?? (try? String(contentsOfFile: Self.addressFile, encoding: .utf8))
        guard
            let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty,
            let url = URL(string: raw)
        else {
            throw XCTSkip("run through scripts/test-live-m1b.sh")
        }
        baseURL = url
    }

    override func tearDownWithError() throws {
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
        directories = []
    }

    /// The whole loop the reviews found broken, in one test: register, verify,
    /// sign in, upload, and read back.
    func testAnAccountCanRegisterVerifySignInAndSynchronize() async throws {
        let email = uniqueEmail()
        let device = try makeDevice()

        try await register(email: email, using: device)
        let session = try await device.api.login(
            email: email,
            password: Self.password,
            device: device.descriptor
        )
        XCTAssertFalse(session.accessToken.isEmpty, "login must return a usable session")

        try await device.credentials.saveActive(session)
        let event = ContractEventFixture.make(id: UUID())
        try await device.store.append(event)

        await device.engine.synchronize(reason: .decisionCompleted)

        let status = await device.engine.status()
        guard case .upToDate = status else {
            return XCTFail("sync status = \(status), want upToDate")
        }
        let pending = try await device.outbox.pendingEventIDs()
        XCTAssertTrue(pending.isEmpty, "an accepted batch must leave the queue empty")
    }

    /// Two installations of one account converge through the real service.
    func testTwoInstallationsConvergeThroughTheRealService() async throws {
        let email = uniqueEmail()
        let phone = try makeDevice()
        let tablet = try makeDevice()

        try await register(email: email, using: phone)
        try await signIn(phone, email: email)
        try await signIn(tablet, email: email)

        let phoneEvent = ContractEventFixture.make(id: UUID())
        let tabletEvent = ContractEventFixture.make(id: UUID())
        try await phone.store.append(phoneEvent)
        try await tablet.store.append(tabletEvent)

        await phone.engine.synchronize(reason: .decisionCompleted)
        await tablet.engine.synchronize(reason: .decisionCompleted)
        await phone.engine.synchronize(reason: .foreground)

        let phoneIDs = try await phone.store.allEvents().map(\.id).sorted()
        let tabletIDs = try await tablet.store.allEvents().map(\.id).sorted()
        let expected = [phoneEvent.id, tabletEvent.id].sorted()

        XCTAssertEqual(phoneIDs, expected)
        XCTAssertEqual(tabletIDs, expected)
        // Counting, not set membership: a duplicated merge would be invisible
        // to a set comparison.
        XCTAssertEqual(phoneIDs.count, 2)
    }

    /// The device list is the one place the client reads back what it sent at
    /// sign-in, so it catches a field the server silently dropped.
    func testTheServerRetainsTheDeviceDetailsTheClientSent() async throws {
        let email = uniqueEmail()
        let device = try makeDevice()
        try await register(email: email, using: device)
        try await signIn(device, email: email)

        let devices = try await device.api.devices(
            accessToken: try await device.authorizer.validAccessToken()
        )

        let current = try XCTUnwrap(devices.first { $0.current })
        XCTAssertEqual(current.displayName, device.descriptor.displayName)
        XCTAssertEqual(current.platform, device.descriptor.platform)
        XCTAssertEqual(
            current.appVersion,
            device.descriptor.appVersion,
            "a field the server drops here is a field it never stored"
        )
    }

    /// Export must come back decodable by the production decoder and carry no
    /// credential material.
    func testExportRoundTripsThroughTheProductionDecoder() async throws {
        let email = uniqueEmail()
        let device = try makeDevice()
        try await register(email: email, using: device)
        try await signIn(device, email: email)
        try await device.store.append(ContractEventFixture.make(id: UUID()))
        await device.engine.synchronize(reason: .decisionCompleted)

        let token = try await device.authorizer.validAccessToken()
        _ = try await device.api.reauthenticate(.password(Self.password), accessToken: token)
        let fresh = try await device.authorizer.validAccessToken()
        let export = try await device.api.export(accessToken: fresh)

        XCTAssertEqual(export.schemaVersion, 1)
        XCTAssertEqual(export.events.count, 1)
        let encoded = String(
            decoding: try JSONEncoder().encode(export.events),
            as: UTF8.self
        )
        for secret in ["accessToken", "refreshToken", "$argon2id$", "tokenHash"] {
            XCTAssertFalse(encoded.contains(secret), "export leaked \(secret)")
        }
    }

    // MARK: - Harness

    private static let password = "a sufficiently long passphrase"

    private struct Device {
        let api: RemoteAccountAPI
        let credentials: CredentialStore
        let authorizer: SessionAuthorizer
        let store: SyncTrackingTrainingEventStore
        let outbox: FileOutboxStore
        let engine: SyncEngine
        let descriptor: DeviceDescriptor
    }

    private func makeDevice() throws -> Device {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "Live-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directories.append(directory)

        let api = RemoteAccountAPI(client: APIClient(baseURL: baseURL))
        let credentials = KeychainCredentialStore(vault: InMemoryVault())
        let authorizer = SessionAuthorizer(store: credentials, api: api)
        let outbox = try FileOutboxStore(directory: directory)
        let store = SyncTrackingTrainingEventStore(
            underlying: try FileTrainingEventStore(directory: directory),
            outbox: outbox
        )
        return Device(
            api: api,
            credentials: credentials,
            authorizer: authorizer,
            store: store,
            outbox: outbox,
            engine: SyncEngine(
                store: store,
                outbox: outbox,
                state: try FileSyncStateStore(directory: directory),
                api: RemoteSyncAPI(baseURL: baseURL),
                authorizer: authorizer
            ),
            descriptor: DeviceDescriptor(
                deviceID: UUID(),
                displayName: "Live Test Device",
                platform: "iOS",
                appVersion: "1.2.3"
            )
        )
    }

    private func register(email: String, using device: Device) async throws {
        try await device.api.register(email: email, password: Self.password)
        try await device.api.verifyEmail(token: try await verificationToken(for: email))
    }

    private func signIn(_ device: Device, email: String) async throws {
        let session = try await device.api.login(
            email: email,
            password: Self.password,
            device: device.descriptor
        )
        try await device.credentials.saveActive(session)
    }

    /// Reads the token from the service's development mailbox, which exists
    /// only outside production.
    private func verificationToken(for email: String) async throws -> String {
        struct Mailbox: Decodable {
            struct Message: Decodable {
                let to: String
                let body: String
            }

            let messages: [Message]
        }

        let url = baseURL.appending(path: "v1/dev/mailbox")
        let (data, _) = try await URLSession.shared.data(from: url)
        let mailbox = try JSONDecoder().decode(Mailbox.self, from: data)
        let token = mailbox.messages.last { $0.to.lowercased() == email.lowercased() }?.body
        return try XCTUnwrap(token, "no verification mail was delivered to \(email)")
    }

    private func uniqueEmail() -> String {
        "live-\(UUID().uuidString.prefix(8).lowercased())@example.test"
    }
}
