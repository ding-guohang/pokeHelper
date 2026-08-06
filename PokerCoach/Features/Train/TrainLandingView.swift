import SwiftUI

struct TrainLandingView: View {
    let dependencies: AppDependencies

    var body: some View {
        ContentUnavailableView(
            "训练",
            systemImage: "suit.spade.fill",
            description: Text(
                dependencies.strategyContentAvailability.disclosureText
            )
        )
        .navigationTitle("训练")
    }
}
