import SwiftUI

enum AppDestination: String, CaseIterable, Identifiable {
    case today
    case learn
    case train
    case review

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .today:
            "今日"
        case .learn:
            "学习"
        case .train:
            "训练"
        case .review:
            "复盘"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            "sun.max.fill"
        case .learn:
            "book.fill"
        case .train:
            "suit.spade.fill"
        case .review:
            "chart.bar.fill"
        }
    }
}

struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedDestination: AppDestination? = .today

    let dependencies: AppDependencies

    var body: some View {
        if horizontalSizeClass == .compact {
            compactNavigation
        } else {
            regularNavigation
        }
    }

    private var compactNavigation: some View {
        TabView(selection: $selectedDestination) {
            ForEach(AppDestination.allCases) { destination in
                NavigationStack {
                    destinationView(destination)
                }
                .tabItem {
                    Label(
                        destination.title,
                        systemImage: destination.systemImage
                    )
                }
                .tag(Optional(destination))
            }
        }
    }

    private var regularNavigation: some View {
        NavigationSplitView {
            List(
                AppDestination.allCases,
                selection: $selectedDestination
            ) { destination in
                Label(
                    destination.title,
                    systemImage: destination.systemImage
                )
                .tag(destination)
            }
            .navigationTitle("手牌教练")
        } detail: {
            NavigationStack {
                destinationView(selectedDestination ?? .today)
            }
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: AppDestination) -> some View {
        switch destination {
        case .today:
            TodayView(dependencies: dependencies)
        case .learn:
            LearnView(dependencies: dependencies)
        case .train:
            TrainLandingView(dependencies: dependencies)
        case .review:
            ReviewView(
                dependencies: dependencies,
                onStartTraining: { selectedDestination = .train }
            )
        }
    }
}
