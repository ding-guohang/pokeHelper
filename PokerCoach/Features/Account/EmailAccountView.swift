import SwiftUI

/// Email registration, login, and password reset.
struct EmailAccountView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case login
        case register
        case reset

        var id: Self { self }

        var title: String {
            switch self {
            case .login: "登录"
            case .register: "注册"
            case .reset: "重置密码"
            }
        }
    }

    @Bindable var controller: AccountSessionController

    @State private var mode: Mode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var resetToken = ""

    var body: some View {
        Form {
            Picker("操作", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("account.mode")

            Section {
                TextField("邮箱", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("account.email")

                if mode != .reset {
                    SecureField("密码", text: $password)
                        .textContentType(mode == .register ? .newPassword : .password)
                        .accessibilityIdentifier("account.password")
                }

                if mode == .reset {
                    TextField("重置验证码", text: $resetToken)
                        .textInputAutocapitalization(.never)
                    SecureField("新密码", text: $password)
                        .textContentType(.newPassword)
                }
            } footer: {
                if mode != .login {
                    Text("密码需要 \(PasswordPolicy.minimumScalars) 到 \(PasswordPolicy.maximumScalars) 个字符。")
                }
            }

            Section {
                Button(primaryTitle) {
                    Task { await submit() }
                }
                .disabled(controller.isBusy || email.isEmpty)
                .accessibilityIdentifier("account.submit")

                if mode == .reset {
                    Button("发送重置邮件") {
                        Task { await controller.requestPasswordReset(email: email) }
                    }
                    .disabled(email.isEmpty)
                }
            }

            if let failure = controller.failure {
                Section {
                    Text(failure.message)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("account.failure")
                }
            }
        }
        .navigationTitle(mode.title)
        .disabled(controller.isBusy)
    }

    private var primaryTitle: String {
        switch mode {
        case .login: "登录"
        case .register: "创建账号"
        case .reset: "设置新密码"
        }
    }

    private func submit() async {
        switch mode {
        case .login:
            await controller.login(email: email, password: password)
        case .register:
            await controller.register(email: email, password: password)
        case .reset:
            await controller.confirmPasswordReset(token: resetToken, newPassword: password)
        }
    }
}
