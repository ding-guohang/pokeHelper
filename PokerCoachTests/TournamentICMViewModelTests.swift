import XCTest
@testable import PokerCoach

@MainActor
final class TournamentICMViewModelTests: XCTestCase {
    func testHeroBubbleFactorAgainstEachOpponent() {
        let viewModel = TournamentICMViewModel()
        viewModel.stacksInput = "1000,1000,1000"
        viewModel.payoutsInput = "500,300,200"
        viewModel.heroSeatInput = "0"
        viewModel.compute()

        XCTAssertNil(viewModel.errorText)
        XCTAssertEqual(viewModel.bubbleFactorLines.count, 2, "英雄应对每位对手各一行")
        // Equal stacks + this ladder → 4/3 for both opponents.
        XCTAssertEqual(viewModel.bubbleFactorLines[0].text, "对 座位 1：1.33")
        XCTAssertEqual(viewModel.bubbleFactorLines[1].text, "对 座位 2：1.33")
        XCTAssertEqual(viewModel.equityLines.count, 3)
    }

    func testAsymmetricStacksGiveDistinctBubbleFactors() {
        let viewModel = TournamentICMViewModel()
        viewModel.stacksInput = "3000,1000,2000"
        viewModel.payoutsInput = "500,300,200"
        viewModel.heroSeatInput = "0"
        viewModel.compute()

        XCTAssertNil(viewModel.errorText)
        // Hero (seat 0) vs seat 1 (short stack): 31/29 → 1.07.
        XCTAssertEqual(viewModel.bubbleFactorLines[0].text, "对 座位 1：1.07")
        // vs seat 2 is an independent computation and differs.
        XCTAssertEqual(viewModel.bubbleFactorLines[1].opponentSeat, 2)
        XCTAssertNotEqual(viewModel.bubbleFactorLines[1].text, viewModel.bubbleFactorLines[0].text)
    }

    func testFlatPayoutsShowReasonPerOpponentButStillShowEquities() {
        let viewModel = TournamentICMViewModel()
        viewModel.stacksInput = "1000,1000,1000"
        viewModel.payoutsInput = "300,300,300"
        viewModel.heroSeatInput = "0"
        viewModel.compute()

        // Equities are valid under flat payouts (each 300); bubble factor is not
        // formable, so each row shows a reason, not a number.
        XCTAssertEqual(viewModel.equityLines.count, 3)
        XCTAssertEqual(viewModel.bubbleFactorLines.count, 2)
        for line in viewModel.bubbleFactorLines {
            XCTAssertFalse(line.text.contains("1."), "平坦派彩不应给出泡沫系数数字：\(line.text)")
            XCTAssertTrue(line.text.contains("无法计算泡沫系数"), "应显示无增益原因：\(line.text)")
        }
    }

    func testEffectiveDepthAndPushFoldZone() {
        let viewModel = TournamentICMViewModel()
        viewModel.stacksInput = "12000,3000"
        viewModel.payoutsInput = "100,60"
        viewModel.bigBlindInput = "1000"
        viewModel.compute()

        XCTAssertNil(viewModel.errorText)
        XCTAssertEqual(viewModel.depthLines.count, 2)
        XCTAssertEqual(viewModel.depthLines[0].text, "座位 0：12 BB")
        XCTAssertEqual(viewModel.depthLines[1].text, "座位 1：3 BB")

        // With a threshold, only the seat at/below it is flagged as push/fold.
        viewModel.pushFoldThresholdInput = "10"
        viewModel.compute()
        XCTAssertNil(viewModel.errorText)
        XCTAssertFalse(viewModel.depthLines[0].text.contains("push/fold"), "12BB 不应标 push/fold")
        XCTAssertTrue(viewModel.depthLines[1].text.contains("push/fold 区"), "3BB 应标 push/fold：\(viewModel.depthLines[1].text)")
    }

    func testDepthInputValidation() {
        let badBigBlind = TournamentICMViewModel()
        badBigBlind.stacksInput = "12000,3000"
        badBigBlind.payoutsInput = "100,60"
        badBigBlind.bigBlindInput = "0"
        badBigBlind.compute()
        XCTAssertNotNil(badBigBlind.errorText)
        XCTAssertTrue(badBigBlind.depthLines.isEmpty)

        let badThreshold = TournamentICMViewModel()
        badThreshold.stacksInput = "12000,3000"
        badThreshold.payoutsInput = "100,60"
        badThreshold.bigBlindInput = "1000"
        badThreshold.pushFoldThresholdInput = "-1"
        badThreshold.compute()
        XCTAssertNotNil(badThreshold.errorText)

        // No big blind → no depth section, equities still shown.
        let noDepth = TournamentICMViewModel()
        noDepth.stacksInput = "12000,3000"
        noDepth.payoutsInput = "100,60"
        noDepth.compute()
        XCTAssertNil(noDepth.errorText)
        XCTAssertTrue(noDepth.depthLines.isEmpty)
        XCTAssertEqual(noDepth.equityLines.count, 2)
    }

    func testInvalidHeroSeatErrorsAndEmptyHeroShowsNoBubbleFactorRows() {
        let outOfRange = TournamentICMViewModel()
        outOfRange.stacksInput = "1000,1000,1000"
        outOfRange.payoutsInput = "500,300,200"
        outOfRange.heroSeatInput = "9"
        outOfRange.compute()
        XCTAssertNotNil(outOfRange.errorText)
        XCTAssertTrue(outOfRange.bubbleFactorLines.isEmpty)

        let noHero = TournamentICMViewModel()
        noHero.stacksInput = "1000,1000,1000"
        noHero.payoutsInput = "500,300,200"
        noHero.heroSeatInput = ""
        noHero.compute()
        XCTAssertNil(noHero.errorText)
        XCTAssertEqual(noHero.equityLines.count, 3, "不填英雄仍显示各家权益")
        XCTAssertTrue(noHero.bubbleFactorLines.isEmpty, "不填英雄不显示泡沫系数行")
    }
}
