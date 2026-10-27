import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var manager: TailscaleManager
    @EnvironmentObject private var keepAlive: BackgroundKeepAlive
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("节点") {
                    TextField("设备名", text: $manager.hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Control URL（留空使用官方云）", text: $manager.controlURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("修改后需要重新连接生效。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Tailscale 登录") {
                    if manager.authKeyStored {
                        Label("已保存 Auth Key", systemImage: "checkmark.seal")
                        Button("删除 Auth Key", role: .destructive) {
                            manager.deleteAuthKey()
                        }
                    } else {
                        Text("未保存 Auth Key，连接后将使用交互式登录。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("锁屏后保持连接", isOn: $keepAlive.enabled)
                } footer: {
                    Text("通过循环播放静音音频让 App 在后台保持运行，Tailscale 连接不会因锁屏断开。会增加耗电。")
                }

                Section {
                    Button("重置节点身份", role: .destructive) {
                        confirmReset = true
                    }
                } footer: {
                    Text("删除本地 tsnet 状态和 Keychain 中的 Auth Key。管理后台里的旧设备记录需要手动清理。")
                }

                Section("关于") {
                    LabeledContent("Bridge 版本", value: manager.bridgeVersion)
                    LabeledContent("App 版本", value: appVersion)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("重置节点身份？", isPresented: $confirmReset) {
                Button("取消", role: .cancel) {}
                Button("重置", role: .destructive) {
                    manager.resetIdentity()
                }
            } message: {
                Text("这会停止连接并删除本地节点状态。")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
