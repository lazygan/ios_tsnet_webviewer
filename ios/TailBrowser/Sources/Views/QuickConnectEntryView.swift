import SwiftUI

struct QuickConnectEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (String, String, Int) -> Void

    @State private var name = ""
    @State private var host = ""
    @State private var portText = "80"
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("快捷连接") {
                    TextField("连接名称（可选）", text: $name)
                    TextField("目标（IP 或机器名）", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("端口", text: $portText)
                        .keyboardType(.numberPad)
                }

                if let validationError {
                    Section {
                        Text(validationError)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("保存后可在首页一键打开。只能访问 tailnet 地址（100.64.0.0/10 或已知机器名）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加快速连接")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        submit()
                    }
                }
            }
        }
    }

    private func submit() {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            validationError = "请输入目标地址"
            return
        }
        guard let port = Int(portText), (1...65535).contains(port) else {
            validationError = "端口必须是 1-65535"
            return
        }
        guard TailWebURL.make(host: trimmedHost, port: port) != nil else {
            validationError = "目标格式不正确"
            return
        }
        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), trimmedHost, port)
        dismiss()
    }
}
