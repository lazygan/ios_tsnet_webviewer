import SwiftUI
import UIKit
import WebKit

final class BrowserModel: ObservableObject {
    let target: BrowserTarget
    let session: WebSession?
    let unavailableReason: String?

    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var errorMessage: String?

    private var progressObservation: NSKeyValueObservation?
    private var proxyReadyObserver: NSObjectProtocol?
    private var errorGeneration = 0

    init(target: BrowserTarget, proxyPort: Int) {
        self.target = target
        if proxyPort > 0 {
            let session = WebSession(proxyPort: proxyPort)
            self.session = session
            self.unavailableReason = nil
            self.progressObservation = session.webView.observe(
                \.estimatedProgress,
                options: [.initial, .new]
            ) { [weak self] webView, _ in
                let value = webView.estimatedProgress
                DispatchQueue.main.async {
                    self?.progress = value
                }
            }
            self.proxyReadyObserver = NotificationCenter.default.addObserver(
                forName: .tailwebProxyReady,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reloadAfterReconnect()
            }
        } else {
            self.session = nil
            self.unavailableReason = "Tailscale 未连接或本地代理未启动。"
        }
    }

    deinit {
        if let proxyReadyObserver {
            NotificationCenter.default.removeObserver(proxyReadyObserver)
        }
    }

    /// After the app returns from the background, tsnet is restarted and any
    /// page connections made against the old node are dead. Reload the page
    /// so it goes back through the fresh proxy.
    private func reloadAfterReconnect() {
        guard let session, session.webView.url != nil else {
            return
        }
        session.webView.reload()
    }

    func loadInitialIfNeeded() {
        guard let session, session.webView.url == nil else {
            return
        }
        session.webView.load(URLRequest(url: target.url))
    }

    func presentError(_ message: String) {
        errorGeneration += 1
        let generation = errorGeneration
        errorMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.errorGeneration == generation else {
                return
            }
            self.errorMessage = nil
        }
    }

    func dismissError() {
        errorGeneration += 1
        errorMessage = nil
    }
}

struct BrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: BrowserModel

    init(target: BrowserTarget, proxyPort: Int) {
        _model = StateObject(wrappedValue: BrowserModel(target: target, proxyPort: proxyPort))
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let session = model.session {
                WebViewContainer(
                    webView: session.webView,
                    model: model,
                    onEdgeExit: { dismiss() }
                )
                .ignoresSafeArea()
            } else {
                ContentUnavailableView(
                    "无法打开",
                    systemImage: "wifi.slash",
                    description: Text(model.unavailableReason ?? "代理未就绪")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if model.isLoading && model.progress < 1 {
                loadingBar
                    .ignoresSafeArea(edges: .top)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) {
            if let message = model.errorMessage {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.opacity)
                    .onTapGesture {
                        model.dismissError()
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.errorMessage)
        // Fill the whole screen and drop the status bar (time/battery) so there
        // is no system-colored strip above the page.
        .statusBarHidden(true)
        .onAppear {
            model.loadInitialIfNeeded()
        }
    }

    private var loadingBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.15))
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * max(model.progress, 0.03))
                    .animation(.linear(duration: 0.2), value: model.progress)
            }
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    let model: BrowserModel
    let onEdgeExit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, onEdgeExit: onEdgeExit)
    }

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator

        if !context.coordinator.didInstallExitGesture {
            let edge = UIScreenEdgePanGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleEdgePan(_:))
            )
            edge.edges = .left
            edge.delegate = context.coordinator
            edge.cancelsTouchesInView = false
            webView.addGestureRecognizer(edge)
            context.coordinator.didInstallExitGesture = true
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        private let model: BrowserModel
        private let onEdgeExit: () -> Void
        var didInstallExitGesture = false

        init(model: BrowserModel, onEdgeExit: @escaping () -> Void) {
            self.model = model
            self.onEdgeExit = onEdgeExit
        }

        @objc func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard gesture.state == .ended else {
                return
            }
            if gesture.translation(in: gesture.view).x > 60 {
                onEdgeExit()
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.isLoading = false
            model.presentError(friendly(error))
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            model.isLoading = false
            model.presentError(friendly(error))
        }

        private func friendly(_ error: Error) -> String {
            let nsError = error as NSError
            switch nsError.code {
            case NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorTimedOut:
                return "无法连接目标：\(nsError.localizedDescription)。请确认 Tailscale 已连接、端口正确，并且目标在 tailnet 内。"
            default:
                return "加载失败：\(nsError.localizedDescription)"
            }
        }
    }
}
