import Foundation

struct BridgeStatus: Decodable {
    let backendState: String
    let authURL: String?
    let selfPeer: PeerInfo?
    let peers: [PeerInfo]
    let proxyPort: Int
    let proxyRunning: Bool
    let lastError: String?
    let version: String?

    enum CodingKeys: String, CodingKey {
        case backendState
        case authURL
        case selfPeer = "self"
        case peers
        case proxyPort
        case proxyRunning
        case lastError
        case version
    }
}

struct PeerInfo: Decodable, Identifiable, Hashable {
    let hostName: String
    let dnsName: String
    let os: String
    let online: Bool
    let tailscaleIPs: [String]
    let exitNode: Bool

    var id: String {
        dnsName.isEmpty ? hostName : dnsName
    }

    var displayName: String {
        if !hostName.isEmpty {
            return hostName
        }
        return dnsName.isEmpty ? "unknown" : dnsName
    }

    var primaryIP: String? {
        tailscaleIPs.first(where: { !$0.contains(":") }) ?? tailscaleIPs.first
    }
}

struct BrowserTarget: Identifiable {
    let host: String
    let port: Int
    let url: URL

    var id: String {
        url.absoluteString
    }
}
