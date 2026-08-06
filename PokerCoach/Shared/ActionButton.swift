import SwiftUI

struct ActionButton: View {
    let title: String
    let isSelected: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        if isSelected {
            button
                .buttonStyle(.borderedProminent)
        } else {
            button
                .buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button(title, action: action)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}
