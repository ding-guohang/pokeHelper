import Foundation
import XCTest
@testable import PokerCoach

@MainActor
final class AccountSessionControllerTests: XCTestCase {
    // The app must open straight into training with no account and no network.
    func testStartupWithoutAnAccountStaysAnonymous() async {
        let harness = Harness()
        harness.api.failEverything = .offline

        await harness.controller.restore()

        XCTAssertEqual(harness.controller.state, .anonymous)
        XCTAssertNil(
            harness.controller.failure,
            "being offline without an account is normal, not an error to show"
        )
    }

    func testStartupRestoresAStoredSession() async throws {
        let harness = Harness()
        try await harness.credentials.saveActive(.fixture())

        await harness.controller.restore()

        XCTAssertEqual(harness.controller.state, .authenticated(harness.expectedSummary))
    }

    // A Keychain that cannot be read must not silently drop the user to
    // anonymous, because that would hide a real failure behind a normal state.
    func testStartupSurfacesAKeychainFailureWithoutLosingTraining() async {
        let harness = Harness(credentials: FailingCredentialStore())

        await harness.controller.restore()

        XCTAssertEqual(harness.controller.state, .anonymous)
        let failure = harness.controller.failure
        XCTAssertNotNil(failure)
        XCTAssertTrue(failure?.message.contains(where: \.isChineseCharacter) ?? false)
    }

    func testRegisterMovesToAwaitingVerification() async {
        let harness = Harness()

        await harness.controller.register(email: "player@example.test", password: validPassword)

        XCTAssertEqual(
            harness.controller.state,
            .awaitingVerification(email: "player@example.test")
        )
    }

    func testRegisterRejectsAWeakPasswordBeforeCallingTheServer() async {
        let harness = Harness()

        await harness.controller.register(email: "player@example.test", password: "short")

        XCTAssertEqual(harness.controller.state, .anonymous)
        XCTAssertNotNil(harness.controller.failure)
        XCTAssertEqual(harness.api.registerCalls, 0)
    }

    func testVerifyEmailAuthenticatesAndStoresTheSession() async throws {
        let harness = Harness()
        await harness.controller.register(email: "player@example.test", password: validPassword)

        await harness.controller.verifyEmail(token: "verification-token")

        XCTAssertEqual(harness.controller.state, .authenticated(harness.expectedSummary))
        let stored = try await harness.credentials.loadActive()
        XCTAssertNotNil(stored, "a verified account must persist its session")
    }

    func testResendVerificationKeepsAwaitingState() async {
        let harness = Harness()
        await harness.controller.register(email: "player@example.test", password: validPassword)

        await harness.controller.resendVerification()

        XCTAssertEqual(
            harness.controller.state,
            .awaitingVerification(email: "player@example.test")
        )
        XCTAssertEqual(harness.api.resendCalls, 1)
    }

    func testLoginAuthenticatesAndPersistsTheSession() async throws {
        let harness = Harness()

        await harness.controller.login(email: "player@example.test", password: validPassword)

        XCTAssertEqual(harness.controller.state, .authenticated(harness.expectedSummary))
        let stored = try await harness.credentials.loadActive()
        XCTAssertNotNil(stored)
    }

    // Wrong password, unknown account, and unverified account must be
    // indistinguishable, matching the server's single authenticationFailed.
    func testLoginFailureIsGenericAndDoesNotRevealAccountExistence() async {
        let harness = Harness()
        harness.api.failEverything = .unauthorized

        await harness.controller.login(email: "player@example.test", password: validPassword)

        XCTAssertEqual(harness.controller.state, .anonymous)
        let message = harness.controller.failure?.message ?? ""
        XCTAssertTrue(message.contains(where: \.isChineseCharacter))
        for leak in ["不存在", "未注册", "未验证", "密码错误"] {
            XCTAssertFalse(message.contains(leak), "login failure leaked \(leak)")
        }
    }

    func testPasswordResetRequestAndConfirmation() async {
        let harness = Harness()

        await harness.controller.requestPasswordReset(email: "player@example.test")
        XCTAssertEqual(harness.api.resetRequestCalls, 1)
        XCTAssertNil(harness.controller.failure)

        await harness.controller.confirmPasswordReset(
            token: "reset-token",
            newPassword: validPassword
        )
        XCTAssertEqual(harness.api.resetConfirmCalls, 1)
    }

    func testPasswordResetConfirmationValidatesTheNewPasswordLocally() async {
        let harness = Harness()

        await harness.controller.confirmPasswordReset(token: "reset-token", newPassword: "weak")

        XCTAssertEqual(harness.api.resetConfirmCalls, 0)
        XCTAssertNotNil(harness.controller.failure)
    }

    func testSignInWithAppleAuthenticates() async {
        let harness = Harness()

        await harness.controller.signInWithApple()

        XCTAssertEqual(harness.controller.state, .authenticated(harness.expectedSummary))
        XCTAssertFalse(harness.apple.lastNonce.isEmpty, "Apple sign-in must carry a nonce")
    }

    func testLinkingAppleRequiresAnAuthenticatedSession() async {
        let harness = Harness()

        await harness.controller.linkApple()

        XCTAssertEqual(harness.api.linkCalls, 0)
        XCTAssertNotNil(harness.controller.failure)
    }

    func testLinkingAppleFromAnAuthenticatedSessionCallsTheServer() async {
        let harness = Harness()
        await harness.controller.login(email: "player@example.test", password: validPassword)

        await harness.controller.linkApple()

        XCTAssertEqual(harness.api.linkCalls, 1)
        XCTAssertNil(harness.controller.failure)
    }

    func testStaleLinkAttemptAsksForReauthentication() async {
        let harness = Harness()
        await harness.controller.login(email: "player@example.test", password: validPassword)
        harness.api.failEverything = .reauthenticationRequired

        await harness.controller.linkApple()

        XCTAssertTrue(harness.controller.needsReauthentication)
        XCTAssertEqual(
            harness.controller.state,
            .authenticated(harness.expectedSummary),
            "needing to reauthenticate must not log the user out"
        )
    }

    // A 401 rotates the refresh token once and replays the original request
    // once. Anything more would turn a transient failure into a token storm.
    func testExpiredAccessTokenRefreshesOnceAndRetriesTheRequestOnce() async throws {
        let harness = Harness()
        try await harness.credentials.saveActive(.fixture())
        await harness.controller.restore()
        harness.api.unauthorizedResponses = 1

        let value = try await harness.authorizer.authorize { token in
            try await harness.api.probe(accessToken: token)
        }

        XCTAssertEqual(value, "ok")
        XCTAssertEqual(harness.api.refreshCalls, 1)
        XCTAssertEqual(harness.api.probeCalls, 2, "one original attempt plus one retry")
    }

    func testASecondUnauthorizedResponseLocksTheProfileAndClearsCredentials() async throws {
        let harness = Harness()
        try await harness.credentials.saveActive(.fixture())
        await harness.controller.restore()
        harness.api.unauthorizedResponses = 2

        do {
            _ = try await harness.authorizer.authorize { token in
                try await harness.api.probe(accessToken: token)
            }
            XCTFail("a second 401 must not succeed")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }

        XCTAssertEqual(harness.api.refreshCalls, 1, "the profile locks instead of refreshing again")
        let cleared = try await harness.credentials.loadActive()
        XCTAssertNil(cleared)
        XCTAssertEqual(harness.controller.state, .locked)
    }

    func testRotatedSessionIsPersistedForTheNextLaunch() async throws {
        let harness = Harness()
        try await harness.credentials.saveActive(.fixture())
        harness.api.unauthorizedResponses = 1

        _ = try await harness.authorizer.authorize { token in
            try await harness.api.probe(accessToken: token)
        }

        let stored = try await harness.credentials.loadActive()
        XCTAssertEqual(stored?.refreshToken, "rotated-refresh-token")
    }

    // Logging out while offline parks the refresh token for later revocation
    // and locks the profile immediately.
    func testOfflineLogoutParksTheRefreshTokenAndClearsTheSession() async throws {
        let harness = Harness()
        try await harness.credentials.saveActive(.fixture())
        await harness.controller.restore()
        harness.api.failEverything = .offline

        await harness.controller.logOut()

        XCTAssertEqual(harness.controller.state, .anonymous)
        let clearedAfterLogout = try await harness.credentials.loadActive()
        XCTAssertNil(clearedAfterLogout)
        let pending = try await harness.credentials.loadPendingRevocation()
        XCTAssertEqual(pending?.refreshToken, StoredSession.fixture().refreshToken)
    }

    private let validPassword = "a-sufficiently-long-passphrase"
}

@MainActor
private final class Harness {
    let api = AccountAPIDouble()
    let apple = AppleAuthorizationClientDouble()
    let credentials: CredentialStore
    let authorizer: SessionAuthorizer
    let controller: AccountSessionController

    init(credentials: CredentialStore = KeychainCredentialStore(vault: InMemoryVault())) {
        self.credentials = credentials
        controller = AccountSessionController(
            api: api,
            credentials: credentials,
            apple: apple,
            policy: PasswordPolicy(blocklist: []),
            device: DeviceDescriptor(
                deviceID: UUID(uuidString: "30000000-0000-4000-8000-000000000003")!,
                displayName: "iPhone",
                platform: "iOS",
                appVersion: "1.0.0"
            )
        )
        authorizer = controller.authorizer
    }

    var expectedSummary: AccountSummary {
        AccountSummary(
            userID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            email: "player@example.test"
        )
    }
}

private struct FailingCredentialStore: CredentialStore {
    func loadActive() async throws -> StoredSession? { throw CredentialStoreError.unavailable }
    func saveActive(_ session: StoredSession) async throws { throw CredentialStoreError.unavailable }
    func replaceActive(
        expectedRefreshToken: String,
        with session: StoredSession
    ) async throws { throw CredentialStoreError.unavailable }
    func clearActive() async throws { throw CredentialStoreError.unavailable }
    func moveRefreshToPendingRevocation() async throws { throw CredentialStoreError.unavailable }
    func loadPendingRevocation() async throws -> PendingSessionRevocation? {
        throw CredentialStoreError.unavailable
    }
    func clearPendingRevocation() async throws { throw CredentialStoreError.unavailable }
}

private final class AppleAuthorizationClientDouble: AppleAuthorizationClient, @unchecked Sendable {
    private(set) var lastNonce = ""

    func requestCredential() async throws -> AppleCredential {
        lastNonce = UUID().uuidString
        return AppleCredential(identityToken: "apple-identity-token", nonce: lastNonce)
    }
}

private final class AccountAPIDouble: StubAccountAPI, @unchecked Sendable {
    enum Behavior {
        case offline
        case unauthorized
        case reauthenticationRequired
    }

    var failEverything: Behavior?
    var unauthorizedResponses = 0

    private(set) var registerCalls = 0
    private(set) var resendCalls = 0
    private(set) var resetRequestCalls = 0
    private(set) var resetConfirmCalls = 0
    private(set) var linkCalls = 0
    private(set) var refreshCalls = 0
    private(set) var probeCalls = 0

    override func register(email: String, password: String) async throws {
        try failIfConfigured()
        registerCalls += 1
    }

    override func verifyEmail(token: String) async throws -> StoredSession {
        try failIfConfigured()
        return .fixture()
    }

    override func resendVerification(email: String) async throws {
        try failIfConfigured()
        resendCalls += 1
    }

    override func login(
        email: String,
        password: String,
        device: DeviceDescriptor
    ) async throws -> StoredSession {
        try failIfConfigured()
        return .fixture()
    }

    override func requestPasswordReset(email: String) async throws {
        try failIfConfigured()
        resetRequestCalls += 1
    }

    override func confirmPasswordReset(token: String, newPassword: String) async throws {
        try failIfConfigured()
        resetConfirmCalls += 1
    }

    override func signInWithApple(
        identityToken: String,
        nonce: String,
        device: DeviceDescriptor
    ) async throws -> StoredSession {
        try failIfConfigured()
        return .fixture()
    }

    override func linkApple(identityToken: String, nonce: String, accessToken: String) async throws {
        try failIfConfigured()
        linkCalls += 1
    }

    override func refresh(refreshToken: String) async throws -> StoredSession {
        try failIfConfigured()
        refreshCalls += 1
        return .fixture(refreshToken: "rotated-refresh-token")
    }

    override func logOut(refreshToken: String) async throws {
        try failIfConfigured()
    }

    func probe(accessToken: String) async throws -> String {
        probeCalls += 1
        if unauthorizedResponses > 0 {
            unauthorizedResponses -= 1
            throw APIError.unauthorized
        }
        return "ok"
    }

    private func failIfConfigured() throws {
        switch failEverything {
        case .offline:
            throw APIError.offline
        case .unauthorized:
            throw APIError.unauthorized
        case .reauthenticationRequired:
            throw APIError.reauthenticationRequired
        case nil:
            break
        }
    }
}
