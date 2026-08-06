import SwiftUI

@main
struct PokerCoachApp: App {
    @State private var bootstrap = AppBootstrap(
        loader: AppDependencies.live,
        corruptedHistoryRecovery:
            AppDependencies.recoverCorruptedTrainingEvents
    )

    var body: some Scene {
        WindowGroup {
            AppBootstrapView(bootstrap: bootstrap)
        }
    }
}
