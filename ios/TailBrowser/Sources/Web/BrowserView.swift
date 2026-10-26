import SwiftUI
import WebKit

final class BrowserModel: ObservableObject {
    let target: BrowserTarget
    let session: WebSession?
    let unavailableReason: String?

    @Published var addressText: String
    @Published var errorMessage: String?
    @Published var isLoading = false

    private var didLoadInitial = false

    init(target: BrowserTarget, proxyPort: Int) {
        self.target = target
        self.addressText = target.url.absoluteString
        if proxyPort > 0 {
            self.session = WebSession(proxyPort: proxyPort)
            self.unavailableReason = nil
        } else {
            self.session = nil
            self.unavailableReason = "Tailscale 未连接或本地代理未启动。"
        }
    }

    func loadInitialIfNeeded() {
        guard !didLoadInitial, let session else {
            return
        }
        didLoadInitial = true
        session.webView.load(URLRequest(url: target.url))
    }

    func submitAddress() {
        guard let session else {
            return
        }
        guard let url = TailWebURL.normalize(addressText) else {
            errorMessage = "地址格式无效"
            return
        }
        addressText = url.absoluteString
        errorMessage = nil
        session.webView.load(URLRequest(url: url))
    }

    func goBack() {
        session?.webView.goBack()
    }

    func goForward() {
        session?.webView.goForward()
    }

    func reload() {
        session?.webView.reload()
    }
}

struct BrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var bookmarks: BookmarkStore
    @StateObject private var model: BrowserModel

    init(target: BrowserTarget, proxyPort: Int) {
        _model = StateObject(wrappedValue: BrowserModel(target: target, proxyPort: proxyPort))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let session = model.session {
                    WebViewContainer(webView: session.webView, model: model)
                        .overlay(alignment: .top) {
                            if model.isLoading {
                                ProgressView()
                                    .padding(6)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                    .padding(.top, 8)
                            }
                        }
                } else {
                    ContentUnavailableView(
                        "无法打开",
                        systemImage: "wifi.slash",
                        description: Text(model.unavailableReason ?? "代理未就绪")
                    )
                }

                if let message = model.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.thinMaterial)
                }

                addressBar
            }
            .navigationTitle(model.target.host)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if !bookmarks.isBookmarked(host: model.target.host, port: model.target.port) {
                            bookmarks.add(
                                name: model.target.host,
                                host: model.target.host,
                                port: model.target.port
                            )
                        }
                    } label: {
                        Image(
                            systemName: bookmarks.isBookmarked(
                                host: model.target.host,
                                port: model.target.port
                            ) ? "star.fill" : "star"
                        )
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        model.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Button {
                        model.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    Spacer()
                    Button {
                        model.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                model.loadInitialIfNeeded()
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            TextField("主机:端口 或完整 URL", text: $model.addressText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    model.submitAddress()
                }
            Button {
                model.submitAddress()
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
            }
        }
        .padding(8)
        .background(.bar)
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    let model: BrowserModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let model: BrowserModel

        init(model: BrowserModel) {
            self.model = model
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.isLoading = true
            model.errorMessage = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.isLoading = false
            if let url = webView.url {
                model.addressText = url.absoluteString
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.isLoading = false
            model.errorMessage = friendly(error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            model.isLoading = false
            model.errorMessage = friendly(error)
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
