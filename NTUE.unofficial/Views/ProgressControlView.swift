import SwiftUI

/// 修業進度管制 — the a04210 page already renders the official 學分檢核表 inline
/// (with the blue/purple/brown course-status colouring and the full per-category
/// credit table). Rather than re-parse 300+ rows (risk of misstating graduation
/// credits) or scrape the fragile PDF popup, we host the real page in an in-app
/// web view that reuses the logged-in session. The page's own
/// 「學生已修習學分檢核表列印」button still works for an official PDF (its
/// window.open target opens inline in this same web view).
struct ProgressControlView: View {
    @State private var isLoading = true

    private static let url = URL(string: "https://nsa.ntue.edu.tw/a04/a04210")!

    var body: some View {
        NTUEWebView(url: Self.url, isLoading: $isLoading)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                if isLoading {
                    ProgressView()
                        .padding(8)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 8)
                }
            }
            .navigationTitle("修業進度管制")
            .navigationBarTitleDisplayMode(.inline)
    }
}
