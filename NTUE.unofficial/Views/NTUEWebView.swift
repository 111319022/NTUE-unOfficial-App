import SwiftUI
import WebKit

/// A WKWebView that reuses the app's logged-in iNTUE session by injecting the
/// shared cookies. Used for features the school only exposes through their web
/// UI (e.g. the official PDF generators).
struct NTUEWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        // Copy the URLSession login cookies into the web view, then load.
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = (HTTPCookieStorage.shared.cookies ?? []).filter { $0.domain.contains("ntue.edu.tw") }
        let group = DispatchGroup()
        for cookie in cookies { group.enter(); store.setCookie(cookie) { group.leave() } }
        group.notify(queue: .main) { webView.load(URLRequest(url: url)) }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: NTUEWebView
        init(_ parent: NTUEWebView) { self.parent = parent }

        private func setLoading(_ value: Bool) {
            DispatchQueue.main.async { self.parent.isLoading = value }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { setLoading(true) }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { setLoading(false) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { setLoading(false) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { setLoading(false) }

        // The PDF button uses window.open — load the popup target in the same view
        // so the generated PDF renders inline.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }
    }
}

/// A sheet that hosts an iNTUE page in `NTUEWebView`.
struct NTUEWebSheet: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            NTUEWebView(url: url, isLoading: $isLoading)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if isLoading {
                        ProgressView()
                            .padding(8)
                            .background(.thinMaterial, in: Capsule())
                            .padding(.top, 8)
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
        }
    }
}
