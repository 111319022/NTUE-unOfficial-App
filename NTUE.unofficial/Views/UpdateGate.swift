import SwiftUI

/// A full-screen blocking overlay shown when the running version is below the
/// `minVersion` set remotely in CloudKit (`AppConfig`). There's intentionally no
/// dismiss — the point is to force an update — so the app is unusable until the
/// user updates. Configure/clear it entirely from the CloudKit Dashboard.
struct UpdateGate: ViewModifier {
    @State private var config = RemoteConfigService.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if config.appConfig.forceUpdateRequired {
                    ForceUpdateView(config: config.appConfig)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: config.appConfig.forceUpdateRequired)
    }
}

extension View {
    /// Blocks the app with a 強制更新 screen when CloudKit says the version is too old.
    func updateGate() -> some View { modifier(UpdateGate()) }
}

private struct ForceUpdateView: View {
    let config: AppConfig

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.accent)
                Text(config.updateTitle ?? "請更新 App")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(config.updateMessage
                     ?? "目前版本已停止支援，請更新到最新版本以繼續使用。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)

                VStack(spacing: 4) {
                    Text("目前版本 \(AppConfig.currentVersion)")
                    if let latest = config.latestVersion, !latest.isEmpty {
                        Text("最新版本 \(latest)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)

                if let urlStr = config.updateURL, let url = URL(string: urlStr) {
                    Link(destination: url) {
                        Text("前往更新")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accentFill)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(28)
            .frame(maxWidth: 360)
        }
    }
}
