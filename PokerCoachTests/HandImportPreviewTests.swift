import Foundation
import HandHistory
import HandHistoryPersistence
import PokerCore
import TrainingPersistence
import XCTest
@testable import PokerCoach

/// The conflict-review surface: what the preview shows and when a hand may be
/// adopted.
///
/// Every assertion pins a value, not its presence. A preview that rendered empty
/// placeholders would "show" a position and a board; the point is that it shows
/// *this* hand's position and board. And a hand with an unread field must not be
/// adoptable until the field is supplied — a gate that were always open would
/// let an incomplete hand into the library.
final class HandImportPreviewTests: XCTestCase {
    // MARK: - 1. Preview values equal model values

    @MainActor
    func testPreviewValuesEqualTheModelValues() async throws {
        // The parser's model, so the preview can be checked against it rather
        // than against a re-description of the input.
        guard case let .parsed(model, conflicts) = PokerStarsParser.parse(HandImportFixtureText.appendixA)
        else {
            return XCTFail("附录 A 应当解析为 .parsed")
        }
        XCTAssertTrue(conflicts.isEmpty, "附录 A 不应有冲突")
        XCTAssertFalse(model.streets.isEmpty, "夹具没有产出任何街道")

        let (viewModel, _) = try makeViewModel()
        viewModel.load(text: HandImportFixtureText.appendixA)
        let preview = try XCTUnwrap(viewModel.preview)

        // Hero position is BTN — equal to the position the model's offset maps
        // to, and to the label the domain defines for it.
        XCTAssertEqual(preview.heroPosition, "BTN")
        XCTAssertEqual(
            preview.heroPosition,
            try TablePosition(tableSize: 6, heroSeatOffsetFromButton: 0).label
        )

        // Hero seat: 100 BB starting stack (10000 centi-BB) and the shown hole
        // cards, both equal to the model's values rather than merely non-empty.
        let heroModel = try XCTUnwrap(model.seats.first { seat in
            if case .known = seat.holeCards { return true }
            return false
        })
        let heroRow = try XCTUnwrap(preview.seats.first { $0.seat == heroModel.seat })
        XCTAssertEqual(heroModel.startingStackCentiBB, 10_000)
        XCTAssertEqual(heroRow.startingStack, "100 BB")
        XCTAssertEqual(heroRow.holeCards, "Ah Kd")
        XCTAssertEqual(heroRow.position, "BTN")

        // Flop board equals the model's cards, rendered as codes.
        let flopModel = try XCTUnwrap(model.streets.first { $0.street == .flop })
        let flopRow = try XCTUnwrap(preview.streets.first { $0.street == .flop })
        XCTAssertEqual(flopRow.board, "Ac 7h 2s")
        XCTAssertEqual(flopRow.board, flopModel.board.map(\.code).joined(separator: " "))

        // Per-street voluntary actions, position-labelled and amount-carrying.
        let preflopRow = try XCTUnwrap(preview.streets.first { $0.street == .preflop })
        XCTAssertEqual(
            preflopRow.actions,
            ["UTG 弃牌", "HJ 弃牌", "CO 弃牌", "BTN 加注至 3 BB", "SB 弃牌", "BB 跟注 3 BB"]
        )
        XCTAssertEqual(flopRow.actions, ["BB 过牌", "BTN 下注 4 BB", "BB 跟注 4 BB"])
        let riverRow = try XCTUnwrap(preview.streets.first { $0.street == .river })
        XCTAssertEqual(riverRow.actions, ["BB 过牌", "BTN 下注 8 BB", "BB 弃牌"])
        // The action count matches the model street-for-street.
        for street in model.streets {
            let row = try XCTUnwrap(preview.streets.first { $0.street == street.street })
            XCTAssertEqual(row.actions.count, street.actions.count)
        }

        // Result: the non-zero rake, as big blinds.
        XCTAssertEqual(model.result.rakeCentiBB, 50)
        XCTAssertEqual(preview.rake, "0.5 BB")
    }

    // MARK: - 2. A hand with a conflict cannot be adopted

    @MainActor
    func testAHandWithAConflictCannotBeAcceptedAndExposesTheFieldAndLine() async throws {
        let (viewModel, libraryStore) = try makeViewModel()
        viewModel.load(text: HandImportFixtureText.appendixB)

        XCTAssertFalse(viewModel.canAccept, "含未解决冲突的牌谱不应可采纳")
        XCTAssertEqual(viewModel.unresolvedConflicts.count, 1)
        let conflict = try XCTUnwrap(viewModel.unresolvedConflicts.first)
        XCTAssertEqual(conflict.field, "action.preflop")
        XCTAssertEqual(conflict.sourceLine, HandImportFixtureText.heroPreflopLine)

        // A preview is still available (the hand parsed well enough to show), but
        // nothing was written.
        XCTAssertNotNil(viewModel.preview)
        let countBefore = try await libraryStore.hands().count
        XCTAssertEqual(countBefore, 0)

        // Accepting while blocked is a no-op.
        try await viewModel.accept()
        let countAfter = try await libraryStore.hands().count
        XCTAssertEqual(countAfter, 0, "被门槛拦住的牌谱不应写入牌库")
    }

    // MARK: - 3. Resolving the conflict opens the gate

    @MainActor
    func testResolvingTheConflictClearsItAndAllowsAdoption() async throws {
        let (viewModel, libraryStore) = try makeViewModel()
        viewModel.load(text: HandImportFixtureText.appendixB)
        let conflict = try XCTUnwrap(viewModel.unresolvedConflicts.first)

        // The user supplies the action the parser refused to guess: the hero
        // raises to 3 BB (300 centi-BB).
        viewModel.resolve(conflict, seat: 1, kind: .raiseTo, amountCentiBB: 300)

        XCTAssertTrue(viewModel.unresolvedConflicts.isEmpty, "修正后冲突应清空")
        XCTAssertTrue(viewModel.canAccept, "冲突清空后应可采纳")

        // The resolved action is placed in the preflop sequence in its original
        // position, not tacked onto the end.
        let preflop = try XCTUnwrap(viewModel.preview?.streets.first { $0.street == .preflop })
        XCTAssertEqual(
            preflop.actions,
            ["UTG 弃牌", "HJ 弃牌", "CO 弃牌", "BTN 加注至 3 BB", "SB 弃牌", "BB 跟注 3 BB"]
        )

        try await viewModel.accept()
        let count = try await libraryStore.hands().count
        XCTAssertEqual(count, 1, "采纳后牌库应当多出一手")
    }

    // MARK: - 4. Conflicts locate to field + line, and a clean hand has none

    @MainActor
    func testConflictsLocateToLineAndACleanHandHasNone() async throws {
        let (twoConflictVM, _) = try makeViewModel()
        twoConflictVM.load(text: HandImportFixtureText.twoConflicts)
        XCTAssertEqual(twoConflictVM.unresolvedConflicts.count, 2, "构造的牌谱应恰有两条冲突")
        XCTAssertEqual(
            twoConflictVM.unresolvedConflicts.map(\.sourceLine).sorted(),
            [HandImportFixtureText.heroPreflopLine, HandImportFixtureText.heroFlopLine]
        )
        XCTAssertFalse(twoConflictVM.canAccept)

        let (cleanVM, _) = try makeViewModel()
        cleanVM.load(text: HandImportFixtureText.appendixA)
        XCTAssertTrue(cleanVM.unresolvedConflicts.isEmpty, "附录 A 在同一视图应显示零冲突")
        XCTAssertTrue(cleanVM.canAccept)
    }

    // MARK: - Support

    @MainActor
    private func makeViewModel() throws -> (HandImportViewModel, FileHandLibraryStore) {
        let libraryStore = try FileHandLibraryStore(directory: temporaryDirectory())
        let eventStore = try FileTrainingEventStore(directory: temporaryDirectory())
        let coordinator = HandImportCoordinator(
            libraryStore: libraryStore,
            eventStore: eventStore
        )
        return (HandImportViewModel(coordinator: coordinator), libraryStore)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}
