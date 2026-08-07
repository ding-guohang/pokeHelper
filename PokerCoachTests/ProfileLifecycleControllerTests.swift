import Foundation
import XCTest
@testable import PokerCoach

@MainActor
final class ProfileLifecycleControllerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "ProfileLifecycle-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testStartingActivatesTheAnonymousProfile() async {
        let controller = makeController()

        await controller.start()

        XCTAssertEqual(controller.active?.id, .anonymous)
    }

    func testSigningInClaimsAnonymousHistoryForTheFirstAccountOnly() async {
        let controller = makeController()
        await controller.start()
        let anonymousLocalID = controller.active?.localUserID

        let firstAccount = UUID()
        await controller.signedIn(remoteUserID: firstAccount)
        let claimed = controller.active

        await controller.signedOut()
        await controller.signedIn(remoteUserID: UUID())
        let second = controller.active

        XCTAssertEqual(claimed?.localUserID, anonymousLocalID)
        XCTAssertNotEqual(second?.localUserID, anonymousLocalID)
        XCTAssertNotEqual(claimed?.directory, second?.directory)
    }

    func testSigningOutReturnsToAnonymous() async {
        let controller = makeController()
        await controller.start()
        await controller.signedIn(remoteUserID: UUID())

        await controller.signedOut()

        XCTAssertEqual(controller.active?.id, .anonymous)
    }

    func testEveryProfileChangeIsPublished() async {
        var observed: [ProfileID] = []
        let controller = makeController { observed.append($0.id) }
        let account = UUID()

        await controller.start()
        await controller.signedIn(remoteUserID: account)
        await controller.signedOut()

        XCTAssertEqual(
            observed,
            [.anonymous, ProfileID(remoteUserID: account), .anonymous]
        )
    }

    private func makeController(
        onChange: @escaping @MainActor (ActiveProfile) -> Void = { _ in }
    ) -> ProfileLifecycleController {
        ProfileLifecycleController(
            profiles: ActiveProfileController(
                associations: ProfileAssociationStore(directory: root),
                directories: ProfileDirectoryProvider(root: root)
            ),
            onProfileChanged: onChange
        )
    }
}
