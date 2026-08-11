import SwiftUI

/// The training tab.
///
/// Its whole content is the cash session: pick a length, play, review the key
/// hands, read the frequency report. Without a session store there is nowhere
/// to record hands, so the tab says so rather than offering a button that
/// cannot finish.
struct TrainLandingView: View {
    let dependencies: AppDependencies

    var body: some View {
        Group {
            if let sessionStore = dependencies.sessionStore {
                SessionView(
                    dependencies: dependencies,
                    sessionStore: sessionStore
                )
            } else {
                ContentUnavailableView(
                    "训练",
                    systemImage: "suit.spade.fill",
                    description: Text(
                        dependencies.strategyContentAvailability.disclosureText
                    )
                )
                .navigationTitle("训练")
            }
        }
    }
}
