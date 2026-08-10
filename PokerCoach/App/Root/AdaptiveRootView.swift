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
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDestination: AppDestination? = .today
    @State private var isShowingAccount = false

    let dependencies: AppDependencies

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactNavigation
            } else {
                regularNavigation
            }
        }
        .sheet(isPresented: $isShowingAccount) {
            NavigationStack {
                AccountCenterView(controller: dependencies.accountSession)
            }
        }
        .task {
            await dependencies.accountSession.restore()
            await dependencies.pendingRevocation.process(trigger: .launch)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await dependencies.pendingRevocation.process(trigger: .foreground) }
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
        content(for: destination)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    accountToolbarItem
                }
            }
    }

    /// The account entry lives in the toolbar of every destination, so signing
    /// in is always one tap away and never a wall in front of training.
    private var accountToolbarItem: some View {
        Button {
            isShowingAccount = true
        } label: {
            if case .anonymous = dependencies.accountSession.state {
                Label(AccountCopy.localOnlySuffix, systemImage: "person.crop.circle")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote)
            } else {
                Label(AccountCopy.toolbarLabel, systemImage: "person.crop.circle.fill")
            }
        }
        .accessibilityIdentifier("account.open")
    }

    @ViewBuilder
    private func content(for destination: AppDestination) -> some View {
        switch destination {
        case .today:
            TodayView(
                dependencies: dependencies,
                onStartTraining: { selectedDestination = .train }
            )
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
