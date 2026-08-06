import Observation
import SwiftUI

@MainActor
@Observable
final class AppBootstrap {
    enum State {
        case loading
        case content(AppDependencies)
        case failure
    }

    typealias Loader = @MainActor () throws -> AppDependencies

    private(set) var state: State = .loading

    @ObservationIgnored
    private let loader: Loader

    init(loader: @escaping Loader) {
        self.loader = loader
    }

    func loadIfNeeded() {
        guard case .loading = state else {
            return
        }
        load()
    }

    func retry() {
        state = .loading
        load()
    }

    private func load() {
        do {
            state = .content(try loader())
        } catch {
            state = .failure
        }
    }
}

struct AppBootstrapView: View {
    let bootstrap: AppBootstrap

    var body: some View {
        Group {
            switch bootstrap.state {
            case .loading:
                ProgressView("正在启动…")
            case let .content(dependencies):
                AdaptiveRootView(dependencies: dependencies)
            case .failure:
                ContentUnavailableView {
                    Label(
                        "无法启动手牌教练",
                        systemImage: "exclamationmark.triangle"
                    )
                } description: {
                    Text("本地数据加载失败，请重试。")
                } actions: {
                    Button("重试") {
                        bootstrap.retry()
                    }
                }
            }
        }
        .task {
            bootstrap.loadIfNeeded()
        }
    }
}
