import SwiftUI

struct LearnView: View {
    let dependencies: AppDependencies

    var body: some View {
        ContentUnavailableView(
            "学习",
            systemImage: "book.fill",
            description: Text("现金局学习内容正在准备中。")
        )
        .navigationTitle("学习")
    }
}
