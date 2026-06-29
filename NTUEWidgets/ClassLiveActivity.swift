import ActivityKit
import WidgetKit
import SwiftUI

/// Lock Screen + Dynamic Island presentation for the class-chain Live Activity.
struct ClassLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            LockScreenLiveView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(s.courseName).font(.headline).lineLimit(1)
                    } icon: {
                        Image(systemName: s.phase == .inClass ? "book.fill" : "clock.fill")
                            .foregroundStyle(s.phase == .inClass ? WTheme.accent : WTheme.amber)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if s.phase != .done {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(s.phase == .inClass ? "下課" : "上課").font(.caption2).foregroundStyle(.secondary)
                            Text(s.pivot, style: .timer)
                                .font(.title3.weight(.bold).monospacedDigit())
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 90)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        if !s.classroom.isEmpty {
                            Label(s.classroom, systemImage: "mappin.and.ellipse")
                        }
                        Spacer()
                        if let next = s.followingCourseName, let start = s.followingStart {
                            Text("接著 \(next) · \(timeString(start))")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: s.phase == .inClass ? "book.fill" : "clock.fill")
                    .foregroundStyle(s.phase == .inClass ? WTheme.accent : WTheme.amber)
            } compactTrailing: {
                if s.phase != .done {
                    Text(s.pivot, style: .timer)
                        .monospacedDigit()
                        .frame(maxWidth: 52)
                }
            } minimal: {
                Image(systemName: s.phase == .inClass ? "book.fill" : "clock.fill")
                    .foregroundStyle(s.phase == .inClass ? WTheme.accent : WTheme.amber)
            }
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

#if DEBUG
extension ClassActivityAttributes.ContentState {
    static let previewInClass = Self(
        phase: .inClass, courseName: "資料結構", classroom: "B201",
        pivot: .now.addingTimeInterval(20 * 60),
        followingCourseName: "演算法", followingClassroom: "B305",
        followingStart: .now.addingTimeInterval(70 * 60))

    static let previewBeforeNext = Self(
        phase: .beforeNext, courseName: "線性代數", classroom: "A103",
        pivot: .now.addingTimeInterval(8 * 60),
        followingCourseName: "計算機概論", followingClassroom: "A210",
        followingStart: .now.addingTimeInterval(88 * 60))
}

#Preview("鎖定畫面", as: .content, using: ClassActivityAttributes(title: "今日課程")) {
    ClassLiveActivity()
} contentStates: {
    ClassActivityAttributes.ContentState.previewInClass
    ClassActivityAttributes.ContentState.previewBeforeNext
}

#Preview("靈動島-展開", as: .dynamicIsland(.expanded), using: ClassActivityAttributes(title: "今日課程")) {
    ClassLiveActivity()
} contentStates: {
    ClassActivityAttributes.ContentState.previewInClass
    ClassActivityAttributes.ContentState.previewBeforeNext
}

#Preview("靈動島-精簡", as: .dynamicIsland(.compact), using: ClassActivityAttributes(title: "今日課程")) {
    ClassLiveActivity()
} contentStates: {
    ClassActivityAttributes.ContentState.previewInClass
}
#endif

private struct LockScreenLiveView: View {
    let state: ClassActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: state.phase == .inClass ? "book.fill" : "clock.fill")
                        .foregroundStyle(state.phase == .inClass ? WTheme.accent : WTheme.amber)
                    Text(state.phase == .inClass ? "上課中" : (state.phase == .beforeNext ? "下一節" : "今日課程"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(state.courseName).font(.title3.weight(.bold)).lineLimit(1)
                if !state.classroom.isEmpty {
                    Label(state.classroom, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let next = state.followingCourseName, let start = state.followingStart {
                    Text("接著 \(next) · \(timeString(start))")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if state.phase != .done {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(state.phase == .inClass ? "距下課" : "距上課")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(state.pivot, style: .timer)
                        .font(.system(size: 30, weight: .bold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(maxWidth: 120, alignment: .trailing)
                }
            }
        }
        .padding(16)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
