import SwiftUI

struct RootView: View {
    @EnvironmentObject private var manager: TailscaleManager
    @EnvironmentObject private var bookmarks: BookmarkStore
    @EnvironmentObject private var keepAlive: BackgroundKeepAlive
    @Environment(\.scenePhase) private var scenePhase

    @State private var keyInput = ""
    @State private var showSettings = false
    @State private var showDiagnostics = false
    @State private var showManualEntry = false
    @State private var showQuickAdd = false
    @State private var safariItem: SafariItem?
    @State private var browserTarget: BrowserTarget?
    @State private var expandedRow: ExpandedRow?
    @State private var draftName = ""
    @State private var draftHost = ""
    @State private var draftPort = ""
    @State private var draftError: String?

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                if manager.state.isRunning {
                    machinesSection
                }
                quickConnectSection
                if !manager.state.isRunning {
                    authKeySection
                }
            }
            .navigationTitle("TailWeb")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showDiagnostics = true
                    } label: {
                        Image(systemName: "stethoscope")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
            }
            .sheet(isPresented: $showManualEntry) {
                TargetEntryView(title: "访问地址", initialHost: "", initialPort: 80) { host, port in
                    open(host: host, port: port)
                }
            }
            .sheet(isPresented: $showQuickAdd) {
                QuickConnectEntryView { name, host, port in
                    bookmarks.add(name: name, host: host, port: port)
                }
            }
            .sheet(item: $safariItem) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
            .fullScreenCover(item: $browserTarget) { target in
                BrowserView(target: target, proxyPort: manager.proxyPort)
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    // Check before restarting the loop: if audio was not
                    // actually running, the process was suspended and tsnet
                    // needs a fresh bind.
                    let keptAlive = keepAlive.isPlaying
                    keepAlive.ensurePlaying()
                    manager.setForeground(true, connectionKeptAlive: keptAlive)
                case .background:
                    manager.setForeground(false)
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .onAppear {
                let keptAlive = keepAlive.isPlaying
                keepAlive.ensurePlaying()
                manager.setForeground(scenePhase == .active, connectionKeptAlive: keptAlive)
            }
        }
    }

    private var connectionSection: some View {
        Section("连接") {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(manager.stateDescription)
                Spacer()
                if manager.proxyPort > 0 {
                    Text("代理 \(manager.proxyPort)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            switch manager.state {
            case .stopped:
                Button("连接 Tailscale") {
                    manager.start()
                }
            case .starting:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在启动…")
                        .foregroundStyle(.secondary)
                }
            case .needsLogin(let url):
                Button("登录 Tailscale") {
                    safariItem = SafariItem(url: url)
                }
                Text("在浏览器中完成登录后返回本 App。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .running:
                Button("停止连接", role: .destructive) {
                    manager.stop()
                }
            case .failed(let message):
                Button("重试连接") {
                    manager.start()
                }
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var machinesSection: some View {
        Section("tailnet 机器") {
            if manager.peers.isEmpty {
                Text("暂未发现其他机器")
                    .foregroundStyle(.secondary)
            }
            ForEach(manager.peers) { peer in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Button {
                            openPeer(peer)
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(peer.online ? Color.green : Color.gray)
                                    .frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(peer.displayName)
                                        .foregroundStyle(.primary)
                                    Text(peer.primaryIP ?? peer.dnsName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            togglePeerEditor(peer)
                        } label: {
                            disclosureIcon(expanded: expandedRow == .peer(peer.id))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(expandedRow == .peer(peer.id) ? "收起配置" : "展开配置")
                    }

                    if expandedRow == .peer(peer.id) {
                        editorCard {
                            TextField("目标（IP 或机器名）", text: $draftHost)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .textFieldStyle(.roundedBorder)
                            HStack(spacing: 10) {
                                TextField("端口", text: $draftPort)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 110)
                                Spacer(minLength: 0)
                                Button("打开") {
                                    openPeerDraft(peer)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            Button {
                showManualEntry = true
            } label: {
                Label("手动输入地址", systemImage: "globe")
            }
        }
    }

    private var quickConnectSection: some View {
        Section {
            if bookmarks.bookmarks.isEmpty {
                Text("还没有快捷连接，点右上角“添加”保存常用地址。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(bookmarks.bookmarks) { bookmark in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Button {
                            openBookmark(bookmark)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.name)
                                        .foregroundStyle(.primary)
                                    Text("\(bookmark.host):\(bookmark.port)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!manager.state.isRunning)

                        Button {
                            toggleBookmarkEditor(bookmark)
                        } label: {
                            disclosureIcon(expanded: expandedRow == .bookmark(bookmark.id))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(expandedRow == .bookmark(bookmark.id) ? "收起配置" : "展开配置")
                    }

                    if expandedRow == .bookmark(bookmark.id) {
                        editorCard {
                            TextField("连接名称（可选）", text: $draftName)
                                .textFieldStyle(.roundedBorder)
                            TextField("目标（IP 或机器名）", text: $draftHost)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .textFieldStyle(.roundedBorder)
                            HStack(spacing: 10) {
                                TextField("端口", text: $draftPort)
                                    .keyboardType(.numberPad)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 110)
                                Spacer(minLength: 0)
                                Button("保存") {
                                    saveBookmarkDraft(bookmark)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Button("打开") {
                                    saveAndOpenBookmark(bookmark)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(!manager.state.isRunning)
                            }
                        }
                    }
                }
            }
            .onDelete(perform: bookmarks.remove)
            if !manager.state.isRunning && !bookmarks.bookmarks.isEmpty {
                Text("连接 Tailscale 后可用")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("快速连接")
                Spacer()
                Button {
                    showQuickAdd = true
                } label: {
                    Image(systemName: "plus")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("添加快捷连接")
            }
        }
    }

    private var authKeySection: some View {
        Section {
            if manager.authKeyStored {
                Label("已保存 Auth Key", systemImage: "checkmark.seal")
                Button("删除 Auth Key", role: .destructive) {
                    manager.deleteAuthKey()
                }
            } else {
                SecureField("tskey-...", text: $keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("保存 Auth Key") {
                    if manager.saveAuthKey(keyInput) {
                        keyInput = ""
                    }
                }
                .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("留空也可以连接，首次会引导到 Tailscale 登录页。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Tailscale 认证（可选）")
        }
    }

    private var statusColor: Color {
        switch manager.state {
        case .running:
            return .green
        case .starting, .needsLogin:
            return .orange
        case .failed:
            return .red
        case .stopped:
            return .gray
        }
    }

    private func disclosureIcon(expanded: Bool) -> some View {
        Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
    }

    private func editorCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
            if let draftError {
                Text(draftError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private func peerHost(_ peer: PeerInfo) -> String {
        peer.primaryIP ?? (peer.hostName.isEmpty ? peer.dnsName : peer.hostName)
    }

    private func peerPort(_ peer: PeerInfo) -> Int {
        bookmarks.lastPort(for: peer.hostName)
            ?? peer.primaryIP.flatMap { bookmarks.lastPort(for: $0) }
            ?? 80
    }

    private func openPeer(_ peer: PeerInfo) {
        open(host: peerHost(peer), port: peerPort(peer), rememberAs: peer.hostName)
    }

    private func togglePeerEditor(_ peer: PeerInfo) {
        if expandedRow == .peer(peer.id) {
            expandedRow = nil
            return
        }
        draftName = ""
        draftHost = peerHost(peer)
        draftPort = String(peerPort(peer))
        draftError = nil
        expandedRow = .peer(peer.id)
    }

    private func openPeerDraft(_ peer: PeerInfo) {
        guard let target = validatedDraftTarget() else {
            return
        }
        expandedRow = nil
        open(host: target.0, port: target.1, rememberAs: peer.hostName)
    }

    private func openBookmark(_ bookmark: Bookmark) {
        guard let url = bookmark.url else {
            return
        }
        open(url: url, host: bookmark.host, port: bookmark.port)
    }

    private func toggleBookmarkEditor(_ bookmark: Bookmark) {
        if expandedRow == .bookmark(bookmark.id) {
            expandedRow = nil
            return
        }
        draftName = bookmark.name
        draftHost = bookmark.host
        draftPort = String(bookmark.port)
        draftError = nil
        expandedRow = .bookmark(bookmark.id)
    }

    @discardableResult
    private func persistBookmarkDraft(_ bookmark: Bookmark) -> Bool {
        guard let target = validatedDraftTarget() else {
            return false
        }
        bookmarks.update(id: bookmark.id, name: draftName, host: target.0, port: target.1)
        return true
    }

    private func saveBookmarkDraft(_ bookmark: Bookmark) {
        if persistBookmarkDraft(bookmark) {
            expandedRow = nil
        }
    }

    private func saveAndOpenBookmark(_ bookmark: Bookmark) {
        guard persistBookmarkDraft(bookmark) else {
            return
        }
        expandedRow = nil
        guard let updated = bookmarks.bookmarks.first(where: { $0.id == bookmark.id }),
              let url = updated.url else {
            return
        }
        open(url: url, host: updated.host, port: updated.port)
    }

    private func validatedDraftTarget() -> (String, Int)? {
        let host = draftHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            draftError = "请输入主机或 IP"
            return nil
        }
        guard let port = Int(draftPort), (1...65535).contains(port),
              TailWebURL.make(host: host, port: port) != nil else {
            draftError = "端口必须是 1-65535"
            return nil
        }
        draftError = nil
        return (host, port)
    }

    private func open(host: String, port: Int, rememberAs memoryKey: String? = nil) {
        guard let url = TailWebURL.make(host: host, port: port) else {
            return
        }
        bookmarks.remember(host: memoryKey ?? host, port: port)
        if let memoryKey, memoryKey != host {
            // Also keep the literal address the user opened, for manual entry.
            bookmarks.remember(host: host, port: port)
        }
        browserTarget = BrowserTarget(host: host, port: port, url: url)
    }

    private func open(url: URL, host: String, port: Int) {
        bookmarks.remember(host: host, port: port)
        browserTarget = BrowserTarget(host: host, port: port, url: url)
    }
}

private enum ExpandedRow: Equatable {
    case peer(String)
    case bookmark(UUID)
}

private struct SafariItem: Identifiable {
    let url: URL

    var id: String {
        url.absoluteString
    }
}
