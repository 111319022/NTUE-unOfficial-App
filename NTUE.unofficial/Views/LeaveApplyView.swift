import SwiftUI

/// 請假申請 — the official form is a Vue-driven write form (date → live period
/// computation, attachment upload, sign-off submit). To guarantee correctness
/// for a write operation, we host the real page in an in-app web view that
/// reuses the logged-in session, rather than re-implementing the submit API.
struct LeaveApplyView: View {
    @State private var isLoading = true

    private static let url = URL(string: "https://nsa.ntue.edu.tw/f01/f01141/add")!

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
            .navigationTitle("請假申請")
            .navigationBarTitleDisplayMode(.inline)
    }
}
