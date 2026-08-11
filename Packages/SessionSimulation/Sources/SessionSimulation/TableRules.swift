import PokerCore

/// The table constants. Every one of them is fixed for M2A.
///
/// They are constants rather than configuration because the proposal fixes
/// them, and because a configurable rake would turn "chips are conserved" into
/// a statement about an undefined quantity — true no matter what the engine
/// does with the pot. Rake is zero and is stated here so the conservation
/// assertion has something to be about.
public enum TableRules {
    /// 6-max: the hero plus five opponents.
    public static let seatCount = 6

    /// Every seat starts every session with 100BB. No rebuy, no seat change,
    /// so a seat that busts stays at zero and the table total never moves.
    public static let startingStack = BBAmount(centiBB: 10_000)

    public static let smallBlind = BBAmount(centiBB: 50)
    public static let bigBlind = BBAmount(centiBB: 100)

    /// Exactly zero in M2A. See the note on this type.
    public static let rake = BBAmount(centiBB: 0)

    /// The hero always sits in seat 0; the button moves instead.
    ///
    /// Fixing one of the two is necessary, and fixing the hero's seat is the
    /// one that makes "the hero's position this hand" a function of the hand
    /// index alone, which is what a replay needs.
    public static let heroSeat = 0

    /// The seat with the button on a given hand.
    ///
    /// Advances one seat per hand, so the hero sees each of the six positions
    /// once every six hands.
    public static func buttonSeat(handIndex: Int) -> Int {
        precondition(handIndex >= 0, "Hand index cannot be negative")
        return handIndex % seatCount
    }

    /// How far a seat sits after the button, in the direction the action moves.
    ///
    /// Offset 1 is the small blind and offset 2 the big blind, matching the
    /// labels `TablePosition` assigns for a six-handed table.
    public static func seatOffsetFromButton(seat: Int, buttonSeat: Int) -> Int {
        (seat - buttonSeat + seatCount) % seatCount
    }

    /// The inverse of `seatOffsetFromButton`.
    public static func seat(atOffset offset: Int, buttonSeat: Int) -> Int {
        (buttonSeat + offset) % seatCount
    }

    /// The label a seat carries this hand — `BTN`, `SB`, `CO` and so on.
    ///
    /// Delegates to `TablePosition` rather than keeping a second copy of the
    /// six labels, so the two cannot drift apart.
    public static func position(seat: Int, buttonSeat: Int) throws(TablePositionError) -> TablePosition {
        try TablePosition(
            tableSize: seatCount,
            heroSeatOffsetFromButton: seatOffsetFromButton(seat: seat, buttonSeat: buttonSeat)
        )
    }
}
