import SwiftUI

struct TodayView: View {
    let dependencies: AppDependencies

    var body: some View {
        ContentUnavailableView(
            "今日",
            systemImage: "sun.max.fill",
            description: Text("完成一次训练后，这里会显示今日计划。")
        )
        .navigationTitle("今日")
    }
}
