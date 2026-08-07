import SwiftUI

/// Account entry point. Reached from a toolbar item on every destination, so
/// it never blocks launch and never becomes a fifth tab.
struct AccountCenterView: View {
    @Bindable var controller: AccountSessionController

    @State private var verificationToken = ""

    var body: some View {
        Form {
            switch controller.state {
            case .anonymous:
                anonymousSection
            case let .awaitingVerification(email):
                verificationSection(email: email)
            case let .authenticated(summary):
                authenticatedSection(summary)
            case .locked:
                lockedSection
            }

            if let failure = controller.failure {
                Section {
                    Text(failure.message)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("account.failure")
                }
            }
        }
        .navigationTitle("账号")
        .disabled(controller.isBusy)
        .task { await controller.restore() }
    }

    private var anonymousSection: some View {
        Section {
            NavigationLink("邮箱登录或注册") {
                EmailAccountView(controller: controller)
            }
            Button("使用 Apple 登录") {
                Task { await controller.signInWithApple() }
            }
            .accessibilityIdentifier("account.signInWithApple")
        } header: {
            Text("尚未登录")
        } footer: {
            Text(AccountCopy.localOnly)
                .accessibilityIdentifier("account.localOnlyNotice")
        }
    }

    private func verificationSection(email: String) -> some View {
        Section {
            Text(email)
            TextField("验证码", text: $verificationToken)
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("account.verificationToken")
            Button("完成验证") {
                Task { await controller.verifyEmail(token: verificationToken) }
            }
            .disabled(verificationToken.isEmpty)
            Button("重新发送验证邮件") {
                Task { await controller.resendVerification() }
            }
        } header: {
            Text("等待邮箱验证")
        } footer: {
            Text("验证完成前，训练记录\(AccountCopy.localOnlySuffix)")
        }
    }

    private func authenticatedSection(_ summary: AccountSummary) -> some View {
        Section {
            LabeledContent("账号", value: summary.email ?? "已通过 Apple 登录")
            Button("绑定 Apple 账号") {
                Task { await controller.linkApple() }
            }
            Button("退出登录", role: .destructive) {
                Task { await controller.logOut() }
            }
            .accessibilityIdentifier("account.logOut")
        } header: {
            Text("已登录")
        } footer: {
            if controller.needsReauthentication {
                Text("该操作需要重新验证身份，请重新登录后再试。")
            }
        }
    }

    private var lockedSection: some View {
        Section {
            NavigationLink("重新登录") {
                EmailAccountView(controller: controller)
            }
        } header: {
            Text("登录状态已失效")
        } footer: {
            Text("本机训练记录未受影响。")
        }
    }
}

enum AccountCopy {
    /// Shown wherever the user is training without an account, so the storage
    /// guarantee is never implicit.
    static let localOnly = "训练记录仅保存在本机。登录后可在多台设备之间同步。"
    static let localOnlySuffix = "仅保存在本机。"
    static let toolbarLabel = "账号"
}
