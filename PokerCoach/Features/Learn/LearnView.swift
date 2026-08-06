import SwiftUI

struct LearnView: View {
    let dependencies: AppDependencies

    var body: some View {
        List {
            Section("M1A 现金局路径") {
                Label("翻前范围", systemImage: "1.circle.fill")
                Label("翻牌持续下注", systemImage: "2.circle.fill")
                Label("下注尺度", systemImage: "3.circle.fill")
                Label("决策复盘", systemImage: "4.circle.fill")
            }

            Section("后续里程碑") {
                LabeledContent("MTT 锦标赛") {
                    Text("后续产品里程碑")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("学习")
    }
}
