import SwiftUI

/// Proves the account holder is present before a sensitive operation.
///
/// This refreshes the existing session rather than signing in again, so the
/// user keeps their place instead of being bounced back to a login screen.
struct RecentAuthenticationView: View {
    @Bindable var controller: AccountSessionController

    var onFinished: () -> Void

    @State private var password = ""

    var body: some View {
        Form {
            Section {
                SecureField("密码", text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("reauth.password")
                Button("验证") {
                    Task {
                        await controller.reauthenticate(.password(password))
                        if controller.failure == nil {
                            onFinished()
                        }
                    }
                }
                .disabled(password.isEmpty || controller.isBusy)
                .accessibilityIdentifier("reauth.submit")
            } header: {
                Text("验证身份")
            } footer: {
                Text("导出和删除等敏感操作需要最近十分钟内验证过身份。")
            }

            Section {
                Button("使用 Apple 验证") {
                    Task {
                        await controller.reauthenticateWithApple()
                        if controller.failure == nil {
                            onFinished()
                        }
                    }
                }
                .accessibilityIdentifier("reauth.apple")
            }

            if let failure = controller.failure {
                Section {
                    Text(failure.message)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("reauth.failure")
                }
            }
        }
        .navigationTitle("验证身份")
        .disabled(controller.isBusy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消", action: onFinished)
            }
        }
    }
}
