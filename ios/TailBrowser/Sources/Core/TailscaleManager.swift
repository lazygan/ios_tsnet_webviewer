import Foundation
import Combine
import UIKit
import Tailbridge

@MainActor
final class TailscaleManager: ObservableObject {
    enum ConnectionState: Equatable {
        case stopped
        case starting
        case needsLogin(URL)
        case running
        case failed(String)

        var isRunning: Bool {
            if case .running = self {
                return true
            }
            return false
        }
    }

    nonisolated static let preferredProxyPort = 43177

    @Published private(set) var state: ConnectionState = .stopped
    @Published private(set) var selfPeer: PeerInfo?
    @Published private(set) var peers: [PeerInfo] = []
    @Published private(set) var proxyPort: Int = 0
    @Published private(set) var lastError: String?
    @Published private(set) var logs: String = ""
    @Published private(set) var authKeyStored: Bool = false

    @Published var hostname: String {
        didSet {
            UserDefaults.standard.set(hostname, forKey: Self.hostnameKey)
        }
    }

    @Published var controlURL: String {
        didSet {
            UserDefaults.standard.set(controlURL, forKey: Self.controlURLKey)
        }
    }

    private static let hostnameKey = "tailweb.hostname"
    private static let controlURLKey = "tailweb.controlURL"

    private var pollTask: Task<Void, Never>?
    private var foreground = true

    init() {
        let defaults = UserDefaults.standard
        hostname = defaults.string(forKey: Self.hostnameKey) ?? "tailweb-ios"
        controlURL = defaults.string(forKey: Self.controlURLKey) ?? ""
        authKeyStored = Keychain.load() != nil
    }

    var bridgeVersion: String {
        TailbridgeVersion()
    }

    func setForeground(_ isForeground: Bool) {
        foreground = isForeground
        if isForeground {
            beginPolling()
            Task { await refreshOnce() }
        } else {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    func start() {
        let authKey = Keychain.load() ?? ""
        let stateDir = Self.stateDirectory()
        let host = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let control = controlURL.trimmingCharacters(in: .whitespacesAndNewlines)

        state = .starting
        lastError = nil

        Task {
            let errorMessage: String? = await Task.detached(priority: .userInitiated) {
                var error: NSError?
                let ok = TailbridgeStart(stateDir, host, authKey, control, Self.preferredProxyPort, &error)
                if ok {
                    return nil
                }
                return error?.localizedDescription ?? "TailbridgeStart failed"
            }.value

            if let errorMessage {
                self.state = .failed(errorMessage)
                self.lastError = errorMessage
            } else {
                self.beginPolling()
                await self.refreshOnce()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        state = .stopped
        peers = []
        selfPeer = nil
        proxyPort = 0
        lastError = nil
        Task.detached(priority: .utility) {
            TailbridgeStop()
        }
    }

    func saveAuthKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }
        let saved = Keychain.save(trimmed)
        authKeyStored = saved
        return saved
    }

    func deleteAuthKey() {
        Keychain.delete()
        authKeyStored = false
    }

    func resetIdentity() {
        let stateDir = Self.stateDirectory()
        stop()
        Task.detached(priority: .utility) {
            var error: NSError?
            _ = TailbridgeResetIdentity(stateDir, &error)
        }
        Keychain.delete()
        authKeyStored = false
    }

    func beginPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.foreground else {
                    return
                }
                await self.refreshOnce()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func refreshOnce() async {
        let json = await Task.detached(priority: .utility) {
            TailbridgeStatusJSON()
        }.value
        let logText = await Task.detached(priority: .utility) {
            TailbridgeLogs()
        }.value

        guard let data = json.data(using: .utf8),
              let status = try? JSONDecoder().decode(BridgeStatus.self, from: data) else {
            return
        }
        apply(status, logs: logText)
    }

    private func apply(_ status: BridgeStatus, logs: String) {
        proxyPort = status.proxyPort
        selfPeer = status.selfPeer
        peers = status.peers.sorted { lhs, rhs in
            if lhs.online != rhs.online {
                return lhs.online && !rhs.online
            }
            return lhs.hostName.localizedCaseInsensitiveCompare(rhs.hostName) == .orderedAscending
        }
        lastError = status.lastError
        if logs != self.logs {
            self.logs = logs
        }

        let nextState: ConnectionState
        switch status.backendState {
        case "Running":
            nextState = .running
        case "NeedsLogin":
            if let raw = status.authURL, let url = URL(string: raw) {
                nextState = .needsLogin(url)
            } else {
                nextState = .starting
            }
        case "Stopped":
            nextState = proxyPort > 0 ? .starting : .stopped
        case "Starting", "NoState", "":
            nextState = .starting
        default:
            if let error = status.lastError, !error.isEmpty {
                nextState = .failed(error)
            } else {
                nextState = .starting
            }
        }
        if state != nextState {
            state = nextState
        }
    }

    func diagnosticsText() async -> String {
        let status = await Task.detached(priority: .utility) {
            TailbridgeStatusJSON()
        }.value
        let logText = await Task.detached(priority: .utility) {
            TailbridgeLogs()
        }.value

        let device = UIDevice.current
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        return """
        TailWeb diagnostics
        app: \(appVersion) (\(build))
        bridge: \(TailbridgeVersion())
        ios: \(device.systemVersion)
        device: \(device.model)
        state: \(stateDescription)
        proxyPort: \(proxyPort)
        tsnet: \(status)
        --- logs ---
        \(logText)
        """
    }

    var stateDescription: String {
        switch state {
        case .stopped:
            return "未连接"
        case .starting:
            return "正在启动"
        case .needsLogin:
            return "需要登录"
        case .running:
            return "已连接"
        case .failed(let message):
            return "错误：\(message)"
        }
    }

    static func stateDirectory() -> String {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ts", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }
}
