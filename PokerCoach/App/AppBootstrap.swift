import Observation
import SwiftUI
import TrainingDomain

@MainActor
@Observable
final class AppBootstrap {
    enum Failure: Equatable {
        case corruptedTrainingHistory(line: Int)
        case unavailable
    }

    enum State {
        case loading
        case content(AppDependencies)
        case failure(Failure)
    }

    typealias Loader = @MainActor () throws -> AppDependencies
    typealias CorruptedHistoryRecovery = @MainActor () throws -> Void

    private(set) var state: State = .loading

    @ObservationIgnored
    private let loader: Loader

    @ObservationIgnored
    private let corruptedHistoryRecovery: CorruptedHistoryRecovery

    init(loader: @escaping Loader) {
        self.loader = loader
        corruptedHistoryRecovery = {
            throw AppBootstrapRecoveryError.unavailable
        }
    }

    init(
        loader: @escaping Loader,
        corruptedHistoryRecovery: @escaping CorruptedHistoryRecovery
    ) {
        self.loader = loader
        self.corruptedHistoryRecovery = corruptedHistoryRecovery
    }

    func loadIfNeeded() {
        guard case .loading = state else {
            return
        }
        load()
    }

    func retry() {
        guard case .failure(.unavailable) = state else {
            return
        }
        state = .loading
        load()
    }

    func recoverCorruptedTrainingHistory() {
        guard case let .failure(.corruptedTrainingHistory(line)) = state else {
            return
        }

        do {
            try corruptedHistoryRecovery()
            state = .loading
            load()
        } catch {
            state = .failure(.corruptedTrainingHistory(line: line))
        }
    }

    private func load() {
        do {
            state = .content(try loader())
        } catch let error as TrainingEventStoreError {
            switch error {
            case let .corruptedLine(line):
                state = .failure(.corruptedTrainingHistory(line: line))
            case .checkpointNotFound:
                state = .failure(.unavailable)
            }
        } catch {
            state = .failure(.unavailable)
        }
    }
}

private enum AppBootstrapRecoveryError: Error {
    case unavailable
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
            case let .failure(failure):
                failureView(failure)
            }
        }
        .task {
            bootstrap.loadIfNeeded()
        }
    }

    @ViewBuilder
    private func failureView(_ failure: AppBootstrap.Failure) -> some View {
        switch failure {
        case let .corruptedTrainingHistory(line):
            ContentUnavailableView {
                Label(
                    "训练历史已损坏",
                    systemImage: "externaldrive.badge.exclamationmark"
                )
            } description: {
                Text(
                    "训练历史第 \(line) 行无法读取。可以保留损坏文件备份、创建新的空白历史，并重试启动。"
                )
            } actions: {
                Button("备份并修复") {
                    bootstrap.recoverCorruptedTrainingHistory()
                }
            }
        case .unavailable:
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
}
