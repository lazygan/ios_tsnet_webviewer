import Foundation
import Network
import WebKit

final class WebSession {
    let proxyPort: Int
    let webView: WKWebView

    init(proxyPort: Int) {
        self.proxyPort = proxyPort

        let identifier = Self.persistentIdentifier()
        let store = WKWebsiteDataStore(forIdentifier: identifier)
        let port = NWEndpoint.Port(rawValue: UInt16(clamping: proxyPort)) ?? .any
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: port)
        var proxy = ProxyConfiguration(socksv5Proxy: endpoint)
        proxy.allowFailover = false
        store.proxyConfigurations = [proxy]

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        self.webView = webView
    }

    private static func persistentIdentifier() -> UUID {
        let key = "tailweb.dataStoreID"
        if let raw = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: raw) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }
}
