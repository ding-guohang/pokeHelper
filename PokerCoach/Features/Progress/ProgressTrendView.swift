import SwiftUI
import TrainingDomain

/// A read-only view of the user's training progress over time, reached from
/// within 复盘. Content-free: it aggregates already-graded decisions by day and
/// shows no strategy content, no recommendations, and writes nothing.
struct ProgressTrendView: View {
    let eventStore: TrainingEventStore

    @State private var viewModel: ProgressTrendViewModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let viewModel {
                    if let summary = viewModel.summaryText {
                        Text(summary)
                            .font(.headline)
                            .accessibilityIdentifier("progress.summary")
                    }

                    if viewModel.dayRows.isEmpty {
                        if viewModel.isLoaded {
                            ContentUnavailableView {
                                Label("还没有训练记录", systemImage: "chart.line.uptrend.xyaxis")
                            } description: {
                                Text("完成决策训练后，这里按天显示你的进步。")
                            }
                            .accessibilityIdentifier("progress.empty")
                        } else {
                            ProgressView()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("每日进度")
                                .font(.headline)
                            ForEach(Array(viewModel.dayRows.enumerated()), id: \.offset) { index, row in
                                Text(row.text)
                                    .accessibilityIdentifier("progress.day.\(index)")
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("训练进度")
        .task {
            if viewModel == nil {
                let created = ProgressTrendViewModel(eventStore: eventStore)
                viewModel = created
                await created.load()
            }
        }
    }
}
