import PokerCore
import SwiftUI

struct PokerCardView: View {
    let card: Card

    var body: some View {
        VStack(spacing: 2) {
            Text(card.rank.rawValue)
                .font(.headline.monospaced())
            Text(card.suit.symbol)
                .font(.title3)
        }
        .foregroundStyle(card.suit.color)
        .frame(minWidth: 44, minHeight: 60)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityText)
    }
}
private extension Card {
    var accessibilityText: String {
        "\(rank.accessibilityText)\(suit.accessibilityText)"
    }
}

private extension Rank {
    var accessibilityText: String {
        switch self {
        case .two: "2"
        case .three: "3"
        case .four: "4"
        case .five: "5"
        case .six: "6"
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"
        case .ten: "10"
        case .jack: "J"
        case .queen: "Q"
        case .king: "K"
        case .ace: "A"
        }
    }
}

private extension Suit {
    var symbol: String {
        switch self {
        case .clubs: "♣"
        case .diamonds: "♦"
        case .hearts: "♥"
        case .spades: "♠"
        }
    }

    var color: Color {
        switch self {
        case .diamonds, .hearts:
            .red
        case .clubs, .spades:
            .primary
        }
    }

    var accessibilityText: String {
        switch self {
        case .clubs: "梅花"
        case .diamonds: "方块"
        case .hearts: "红桃"
        case .spades: "黑桃"
        }
    }
}
