import SwiftUI

struct TrainLandingView: View {
    let dependencies: AppDependencies

    var body: some View {
        ContentUnavailableView(
            "训练",
            systemImage: "suit.spade.fill",
            description: Text("训练场景准备完成后会显示在这里。")
        )
        .navigationTitle("训练")
    }
}
