import SwiftUI

struct TargetEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let onOpen: (String, Int) -> Void

    @State private var host: String
    @State private var portText: String
    @State private var validationError: String?

    init(
        title: String,
        initialHost: String,
        initialPort: Int,
        onOpen: @escaping (String, Int) -> Void
    ) {
        self.title = title
        self.onOpen = onOpen
        _host = State(initialValue: initialHost)
        _portText = State(initialValue: String(initialPort))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("目标") {
                    TextField("主机或 IP", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
                    Text("只能访问 tailnet 地址（100.64.0.0/10 或已知机器名）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("打开") {
                        submit()
                    }
                }
            }
        }
    }

    private func submit() {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationError = "请输入主机或 IP"
            return
        }
        guard let port = Int(portText), (1...65535).contains(port) else {
            validationError = "端口必须是 1-65535"
            return
        }
        onOpen(trimmed, port)
        dismiss()
    }
}
