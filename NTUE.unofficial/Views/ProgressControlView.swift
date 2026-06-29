import SwiftUI
import WebKit
import Combine

/// 修業進度管制 — produces the official 學生已修習學分檢核表 PDF and shows it
/// directly in QuickLook, instead of presenting the school's web page.
///
/// The a04210 print button uses `setSubmit(this,1,0)` (not a guessable
/// `event=` value), so the form POST can't be replicated natively. Instead we
/// load the page in a hidden-but-mounted web view that reuses the logged-in
/// session, click the page's own「…列印」button, and capture the report URL.
///
/// Capture is done by **overriding `window.open` in JS** and posting the URL
/// back through a message handler — this is exactly what the school's page does
/// (its print handler calls `window.open(reportURL)`), and it avoids the
/// `createWebViewWith` gesture/window quirks that made earlier attempts hang.
@MainActor
final class ProgressPDFLoader: NSObject, ObservableObject {
    enum LoadState {
        case loading
        case ready(URL)
        case failed(String)
    }

    @Published var state: LoadState = .loading
    @Published private(set) var webView: WKWebView?

    private var didTriggerPrint = false
    private var didCapture = false
    private var hasStarted = false
    private var generation = 0
    private var steps: [String] = []

    private static let pageURL = URL(string: "https://nsa.ntue.edu.tw/a04/a04210")!

    /// Injected at document start on every page so the print handler's
    /// `window.open(reportURL)` is routed to native instead of opening a popup.
    private static let bridgeScript = """
    (function() {
      window.open = function(u) {
        try { window.webkit.messageHandlers.bridge.postMessage({ t: 'open', u: String(u) }); } catch (e) {}
        return null;
      };
    })();
    """

    /// Finds and clicks the page's own check-table print button. Returns
    /// `clicked:<outerHTML>` so we can see what was triggered, or `notfound`.
    private static let triggerScript = """
    (function() {
      function pick() {
        var all = document.querySelectorAll('*');
        for (var i = 0; i < all.length; i++) {
          var el = all[i];
          var oc = el.getAttribute ? (el.getAttribute('onclick') || '') : '';
          var label = (el.textContent || '') + ' ' + (el.value || '');
          if (oc.indexOf('setSubmit') !== -1 && label.indexOf('列印') !== -1) return el;
        }
        var c = document.querySelectorAll('a, button, input[type=button], input[type=submit]');
        for (var j = 0; j < c.length; j++) {
          var t = (c[j].textContent || '') + ' ' + (c[j].value || '');
          if (t.indexOf('列印') !== -1) return c[j];
        }
        return null;
      }
      var el = pick();
      if (!el) return 'notfound';
      var html = (el.outerHTML || '').replace(/\\s+/g, ' ').slice(0, 160);
      el.click();
      return 'clicked:' + html;
    })()
    """

    /// Kicks off the flow once per appearance; safe to call from `.task`.
    func startIfNeeded() {
        guard !hasStarted else { return }
        start()
    }

    func start() {
        hasStarted = true
        state = .loading
        didTriggerPrint = false
        didCapture = false
        steps = []
        generation += 1
        let gen = generation

        let controller = WKUserContentController()
        controller.add(self, name: "bridge")
        controller.addUserScript(WKUserScript(source: Self.bridgeScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView

        // Reuse the URLSession login cookies, then load the page.
        let store = config.websiteDataStore.httpCookieStore
        let cookies = (HTTPCookieStorage.shared.cookies ?? []).filter { $0.domain.contains("ntue.edu.tw") }
        let group = DispatchGroup()
        for cookie in cookies { group.enter(); store.setCookie(cookie) { group.leave() } }
        group.notify(queue: .main) {
            webView.load(URLRequest(url: Self.pageURL))
        }

        // Safety net so the UI can't hang forever if the page or report stalls.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            guard let self, gen == self.generation else { return }
            if case .loading = self.state {
                let trail = self.steps.isEmpty ? "無" : self.steps.joined(separator: " → ")
                self.fail("產生逾時。\n診斷：\(trail)")
            }
        }
    }

    private func log(_ s: String) { steps.append(s) }

    private func teardown() {
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView = nil
    }

    private func fail(_ message: String) {
        if case .ready = state { return }
        teardown()
        state = .failed(message)
    }

    private func capture(reportURL: URL, via source: String) {
        guard !didCapture else { return }
        didCapture = true
        log("capture(\(source))")
        Task {
            do {
                let fileURL = try await NTUEService.shared.downloadReportPDF(
                    from: reportURL.absoluteString,
                    referer: Self.pageURL.absoluteString,
                    filename: "修業進度檢核表.pdf")
                self.teardown()
                self.state = .ready(fileURL)
            } catch {
                self.fail(error.localizedDescription)
            }
        }
    }
}

extension ProgressPDFLoader: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              body["t"] as? String == "open",
              let urlString = body["u"] as? String,
              let url = URL(string: urlString) else { return }
        log("open:\(urlString.prefix(60))")
        capture(reportURL: url, via: "window.open")
    }
}

extension ProgressPDFLoader: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        log("load:\(webView.url?.absoluteString.prefix(50) ?? "")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        log("finish:\(webView.url?.lastPathComponent ?? "")")
        guard !didTriggerPrint else { return }
        didTriggerPrint = true
        webView.evaluateJavaScript(Self.triggerScript) { [weak self] result, error in
            guard let self else { return }
            let r = (result as? String) ?? "err:\(error?.localizedDescription ?? "nil")"
            self.log("click:\(r.prefix(120))")
            if !r.hasPrefix("clicked") {
                self.fail("找不到列印按鈕，請確認登入狀態後再試。")
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }

    // Fallbacks in case the report opens as a real popup or a main-frame PDF.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { capture(reportURL: url, via: "popup") }
        return nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.response.mimeType == "application/pdf",
           let url = navigationResponse.response.url {
            capture(reportURL: url, via: "pdf-nav")
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

/// Mounts a pre-built `WKWebView` so it lives in the view hierarchy.
private struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ProgressControlView: View {
    @StateObject private var loader = ProgressPDFLoader()

    var body: some View {
        ZStack {
            // Hidden but mounted: window.open only reaches a web view in a window.
            if let webView = loader.webView {
                WebViewHost(webView: webView)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }

            switch loader.state {
            case .loading:
                ProgressView("正在產生修業進度 PDF…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            case .failed(let message):
                ContentUnavailableView {
                    Label("產生失敗", systemImage: "doc.questionmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("重試") { loader.start() }
                        .buttonStyle(.borderedProminent)
                }
                .background(Theme.background)
            case .ready(let url):
                QuickLookPreview(url: url).ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle("修業進度管制")
        .navigationBarTitleDisplayMode(.inline)
        .task { loader.startIfNeeded() }
    }
}
