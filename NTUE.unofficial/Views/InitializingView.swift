import SwiftUI

/// 初始化畫面 —— 冷啟動時在等校務系統回應，以及剛登入完在抓學籍資料時，
/// 使用者看到的就是這一頁。
///
/// 進度不是裝飾用的假動畫：`AppState.bootStep` 走到哪一步，樓裡的燈就亮到哪，
/// 下面的清單也跟著勾起來。
struct InitializingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false
    @State private var takingLong = false

    private var step: AppState.BootStep { appState.bootStep }

    /// 四個步驟 → 十二扇窗，一步亮三扇。
    private var litWindows: Int { (step.rawValue + 1) * 3 }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                CampusScene(litWindows: litWindows, appeared: appeared)
                    .frame(height: 262)

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        AuthEyebrow(text: "Setting up")
                            .authReveal(appeared, 0)
                        AuthTitle(text: "正在把你的資料\n搬進來")
                            .authReveal(appeared, 1)
                    }

                    progressRule
                        .authReveal(appeared, 2)

                    steps
                        .authReveal(appeared, 3)

                    if takingLong {
                        AuthNotice(text: "學校的系統偶爾會慢一點，這裡會等它，不用重開。")
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 12)

                VStack(spacing: 8) {
                    if !appState.username.isEmpty {
                        Text("以 \(appState.username) 登入")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Text("資料直接向 iNTUE 校務系統與 Moodle 取得，不經過其他伺服器。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .authReveal(appeared, 4)
            }
        }
        .animation(.spring(duration: 0.5), value: step)
        .animation(.spring(duration: 0.4), value: takingLong)
        .onAppear { appeared = true }
        .onChange(of: step) { _, _ in AuthHaptic.step() }
        .task {
            // 等超過這個時間，就跟使用者說一聲，別讓人以為當掉了。
            try? await Task.sleep(for: .seconds(9))
            takingLong = true
        }
    }

    // MARK: - 進度線

    private var progressRule: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(10, geo.size.width * CGFloat(step.rawValue + 1) / 4))
            }
        }
        .frame(height: 3)
    }

    // MARK: - 步驟清單

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(AppState.BootStep.allCases, id: \.rawValue) { item in
                HStack(spacing: 12) {
                    marker(for: item)
                        .frame(width: 18, height: 18)

                    Text(item.label)
                        .font(.system(size: 15, weight: item == step ? .semibold : .regular))
                        .foregroundStyle(color(for: item))

                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在準備，目前進行到\(step.label)")
    }

    private func color(for item: AppState.BootStep) -> Color {
        if item < step { return .secondary }
        if item == step { return .primary }
        return Color.primary.opacity(0.28)
    }

    @ViewBuilder
    private func marker(for item: AppState.BootStep) -> some View {
        if item < step {
            ZStack {
                Circle().fill(Theme.accentSoft)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.accent)
            }
            .transition(.scale.combined(with: .opacity))
        } else if item == step {
            activeMarker
        } else {
            Circle()
                .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1.5)
                .padding(3)
        }
    }

    /// 進行中的那一步：一顆點加上一圈往外擴散的漣漪。
    private var activeMarker: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let p = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6

            ZStack {
                Circle()
                    .stroke(Theme.accent.opacity(reduceMotion ? 0 : (1 - p) * 0.5), lineWidth: 1.5)
                    .scaleEffect(0.45 + p * 0.55)
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

#Preview {
    InitializingView()
        .environment(AppState())
}
