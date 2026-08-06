import SwiftUI

struct ReviewView: View {
    let dependencies: AppDependencies

    var body: some View {
        ContentUnavailableView(
            "复盘",
            systemImage: "chart.bar.fill",
            description: Text("完成训练后，这里会显示复盘记录。")
        )
        .navigationTitle("复盘")
    }
}
