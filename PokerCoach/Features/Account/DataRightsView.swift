import SwiftUI

/// Export and account deletion. Both require a recent authentication, so the
/// screen offers the reauthentication prompt inline rather than failing the
/// user at the last step.
struct DataRightsView: View {
    @Bindable var controller: AccountSessionController

    @State private var exportedBundle: URL?
    @State private var deletionChoice: LocalDeletionChoice = .keepAnonymized
    @State private var isConfirmingDeletion = false
    @State private var isReauthenticating = false

    var body: some View {
        Form {
            Section {
                Button("导出我的数据") {
                    Task { await export() }
                }
                .accessibilityIdentifier("account.export")

                if let exportedBundle {
                    ShareLink(item: exportedBundle) {
                        Label("分享导出文件", systemImage: "square.and.arrow.up")
                    }
                    Text(exportedBundle.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("数据导出")
            } footer: {
                Text("导出内容包含账号信息、设备列表和训练记录，不包含任何密码或令牌。")
            }

            Section {
                Picker("本机训练记录", selection: $deletionChoice) {
                    ForEach(LocalDeletionChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.inline)
                .accessibilityIdentifier("account.deletionChoice")

                Text(deletionChoice.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("删除账号", role: .destructive) {
                    isConfirmingDeletion = true
                }
                .accessibilityIdentifier("account.delete")
            } header: {
                Text("删除账号")
            }

            if controller.needsReauthentication {
                Section {
                    Button("重新验证身份") {
                        isReauthenticating = true
                    }
                    .accessibilityIdentifier("account.reauthenticate")
                } footer: {
                    Text("出于安全考虑，导出和删除需要最近十分钟内验证过身份。")
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
        .navigationTitle("数据与隐私")
        .disabled(controller.isBusy)
        .confirmationDialog(
            "确认删除账号？",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task { await controller.deleteAccount(localChoice: deletionChoice) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(deletionChoice.explanation)
        }
        .sheet(isPresented: $isReauthenticating) {
            NavigationStack {
                RecentAuthenticationView(controller: controller) {
                    isReauthenticating = false
                }
            }
        }
    }

    private func export() async {
        let destination = FileManager.default.temporaryDirectory.appending(
            path: "PokerCoachExport-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        exportedBundle = await controller.exportAccount(to: destination)
    }
}
