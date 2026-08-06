import SwiftUI

@main
struct PokerCoachApp: App {
    private let dependencies: AppDependencies

    init() {
        do {
            dependencies = try AppDependencies.live()
        } catch {
            preconditionFailure("无法初始化 APP 依赖：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AdaptiveRootView(dependencies: dependencies)
        }
    }
}
