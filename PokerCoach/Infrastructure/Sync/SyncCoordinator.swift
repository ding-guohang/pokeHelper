import Foundation
import Observation
import TrainingDomain

/// Connects the account lifecycle to the profile and sync layers.
///
/// Each of those layers is deliberately unaware of the others, which keeps them
/// testable in isolation — but something has to assemble them or the app ships
/// with none of it running. That assembly lives here so the wiring is one
/// readable object rather than scattered across view code.
@MainActor
@Observable
final class SyncCoordinator {
    private(set) var status: SyncStatus = .idle

    @ObservationIgnored
    private let account: AccountSessionController
    @ObservationIgnored
    private let profiles: ActiveProfileController
    @ObservationIgnored
    private let root: URL
    @ObservationIgnored
    private let makeEngine: @MainActor (ActiveProfile) throws -> SyncEngine
    @ObservationIgnored
    private let onProfileChanged: @MainActor (ActiveProfile) -> Void

    @ObservationIgnored
    private var engine: SyncEngine?
    @ObservationIgnored
    private var lastKnownUserID: UUID?

    init(
        account: AccountSessionController,
        profiles: ActiveProfileController,
        root: URL,
        makeEngine: @escaping @MainActor (ActiveProfile) throws -> SyncEngine,
        onProfileChanged: @escaping @MainActor (ActiveProfile) -> Void = { _ in }
    ) {
        self.account = account
        self.profiles = profiles
        self.root = root
        self.makeEngine = makeEngine
        self.onProfileChanged = onProfileChanged

        // Wired here rather than inside the account controller so the account
        // layer never needs to know how local data is laid out.
        account.onAccountDeleted = { [weak self] userID, choice in
            await self?.applyAccountDeletion(userID: userID, choice: choice)
        }
    }

    /// Called once at launch, after the account controller has restored.
    func start() async {
        await adoptCurrentProfile()
        await synchronize(reason: .launch)
    }

    /// Called whenever the account state may have changed.
    func accountStateChanged() async {
        guard case let .authenticated(summary) = account.state else {
            if lastKnownUserID != nil {
                lastKnownUserID = nil
                await lockProfile()
            }
            return
        }
        guard summary.userID != lastKnownUserID else {
            return
        }
        lastKnownUserID = summary.userID
        await claimProfile(for: summary.userID)
        await synchronize(reason: .authenticated)
    }

    func synchronize(reason: SyncReason) async {
        guard let engine else {
            return
        }
        await engine.synchronize(reason: reason)
        status = await engine.status()
    }

    func retry() async {
        await synchronize(reason: .manualRetry)
    }

    private func adoptCurrentProfile() async {
        guard let profile = try? await profiles.current() else {
            return
        }
        await install(profile)
    }

    private func claimProfile(for userID: UUID) async {
        guard let profile = try? await profiles.claimCurrent(remoteUserID: userID) else {
            return
        }
        await install(profile)
    }

    private func lockProfile() async {
        try? await profiles.lockCurrent()
        await adoptCurrentProfile()
    }

    private func applyAccountDeletion(
        userID: UUID,
        choice: LocalDeletionChoice
    ) async {
        lastKnownUserID = nil
        guard let profile = try? await profiles.applyLocalDeletion(
            choice,
            remoteUserID: userID
        ) else {
            return
        }
        await install(profile)
    }

    private func install(_ profile: ActiveProfile) async {
        account.activeProfile = profile
        engine = try? makeEngine(profile)
        onProfileChanged(profile)
        status = .idle
    }
}
