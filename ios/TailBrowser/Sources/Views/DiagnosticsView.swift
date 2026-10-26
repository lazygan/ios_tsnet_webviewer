import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var manager: TailscaleManager
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .textSelection(.enabled)
            }
            .navigationTitle("诊断")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("刷新") {
                        refresh()
                    }
                    ShareLink(item: text) {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .onAppear {
                refresh()
            }
        }
    }

    private func refresh() {
        Task {
            text = await manager.diagnosticsText()
        }
    }
}
