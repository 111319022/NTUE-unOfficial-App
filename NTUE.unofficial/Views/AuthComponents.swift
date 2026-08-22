import SwiftUI
import UIKit

// MARK: - 排版

/// 標題上方的那行小字：等寬、全大寫、拉開字距。整個登入 / 初始化流程靠它
/// 建立節奏感，也讓標題不必再靠圖示來撐場面。
struct AuthEyebrow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(2.2)
            .textCase(.uppercase)
            .foregroundStyle(Theme.accent)
    }
}

/// 襯線體大標。中文在 iOS 上會落在宋體，和內文的黑體拉出對比。
struct AuthTitle: View {
    let text: String
    var size: CGFloat = 27

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .serif))
            .tracking(-0.4)
            .lineSpacing(4)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct AuthBody: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .lineSpacing(4)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 按鈕

struct AuthPrimaryButton: View {
    let title: String
    var busyTitle: String = ""
    var isBusy: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(isBusy ? busyTitle : title)
                    .font(.system(size: 17, weight: .bold))
                    .tracking(0.4)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background(isEnabled || isBusy ? Theme.accentFill : Theme.accentFill.opacity(0.3),
                        in: Capsule())
        }
        .disabled(!isEnabled || isBusy)
        .buttonStyle(PressScaleStyle())
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
        .animation(.spring(duration: 0.35), value: isBusy)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

// MARK: - 提示

/// 錯誤訊息：左邊一條酒紅色的細線，而不是驚嘆號圖示 —— 像編輯過的排版，
/// 不像系統警告。
struct AuthNotice: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(Theme.accent)
                .frame(width: 2.5)
            Text(text)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        // 沒有這行的話，左邊那條線會被外層 VStack 拉到整頁那麼長。
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 2)
    }
}

// MARK: - 進場動畫

/// 依序淡入 + 上浮，`index` 決定先後。整個流程共用同一組節奏。
private struct AuthRevealModifier: ViewModifier {
    let isActive: Bool
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .offset(y: isActive || reduceMotion ? 0 : 16)
            .animation(
                .spring(duration: 0.55, bounce: 0.2).delay(0.10 + 0.07 * Double(index)),
                value: isActive
            )
    }
}

extension View {
    func authReveal(_ isActive: Bool, _ index: Int) -> some View {
        modifier(AuthRevealModifier(isActive: isActive, index: index))
    }
}

// MARK: - 觸覺回饋

enum AuthHaptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func commit() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func step() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func failure() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
