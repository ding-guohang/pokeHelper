import SwiftUI

@main
struct PokerCoachApp: App {
    @State private var bootstrap = AppBootstrap(
        loader: AppDependencies.live
    )

    var body: some Scene {
        WindowGroup {
            AppBootstrapView(bootstrap: bootstrap)
        }
    }
}
