import SwiftUI

/// Lists the account's own device sessions and lets the user revoke another
/// one. The server refuses a session the caller does not own, so this screen
/// never has to reason about ownership itself.
struct DeviceSessionsView: View {
    @Bindable var controller: AccountSessionController

    @State private var devices: [DeviceSessionDTO] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if devices.isEmpty, !isLoading {
                ContentUnavailableView(
                    "暂无其他设备",
                    systemImage: "iphone",
                    description: Text("登录其他设备后会显示在这里。")
                )
            }

            ForEach(devices) { device in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(device.displayName)
                            .font(.headline)
                        if device.current {
                            Text("当前设备")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("device.current")
                        }
                    }
                    Text("\(device.platform) · \(device.appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("最近活动 \(device.lastActiveAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    if !device.current {
                        Button("退出该设备", role: .destructive) {
                            Task { await revoke(device) }
                        }
                    }
                }
            }
        }
        .navigationTitle("设备")
        .overlay { if isLoading { ProgressView() } }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        isLoading = true
        devices = await controller.loadDevices()
        isLoading = false
    }

    private func revoke(_ device: DeviceSessionDTO) async {
        await controller.revokeDevice(sessionID: device.sessionID)
        await reload()
    }
}
