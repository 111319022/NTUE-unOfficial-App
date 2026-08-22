import SwiftUI

/// 校園小景 —— 登入與初始化畫面共用的插圖。
///
/// 這張圖不只是裝飾：主樓的窗戶會依 `litWindows` 一格一格亮起，初始化時那就是
/// 進度本身；塔樓上的時鐘走的是真正的時間。整張圖畫在 320×214 的座標系裡，
/// 再等比縮放去填滿外框，所以無論放在多高的區塊裡比例都不會跑掉。
struct CampusScene: View {
    /// 亮著的窗戶數（0...12）。
    var litWindows: Int = 5
    /// 入場動畫的開關；由外層在 `onAppear` 打開。
    var appeared: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 窗戶亮起的順序刻意打散，看起來才像真的有人一間一間去開燈，
    // 而不是一條由左到右的進度條。
    private static let lightOrder = [5, 2, 8, 11, 1, 6, 3, 9, 0, 7, 10, 4]

    // 畫布高度只留到地平線再往下一點點。之前留了 40pt 的空地，等比縮放時
    // 那段空白會反過來把整棟樓壓小，畫面左右也跟著留白。
    private static let designSize = CGSize(width: 320, height: 186)
    private static let groundY: CGFloat = 172

    var body: some View {
        ZStack {
            wash
            DesignCanvas(size: Self.designSize) { scene }
        }
        .clipped()
    }

    // MARK: - 背景

    private var wash: some View {
        ZStack {
            LinearGradient(
                colors: [Theme.accent.opacity(0.13), Theme.accent.opacity(0.03)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Theme.amber.opacity(0.22), .clear],
                center: UnitPoint(x: 0.55, y: 0.72),
                startRadius: 4, endRadius: 190
            )
        }
    }

    // MARK: - 主場景

    private var scene: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

            ZStack(alignment: .topLeading) {
                cloud(t: t)
                birds(t: t)

                flag(t: t)
                tower
                mainBlock
                plinth

                tree
                lamp(t: t)
                bush

                ground
            }
            .environment(\.sceneClockDate, timeline.date)
        }
    }

    // MARK: - 建築

    private var tower: some View {
        ZStack(alignment: .topLeading) {
            // 塔身
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Ink.wallShade)
                .place(60, 30, 40, Self.groundY - 30)

            // 屋簷
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Ink.roof)
                .place(54, 24, 52, 8)

            clockFace.place(67, 41, 26, 26)

            // 拱門
            UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10, style: .continuous)
                .fill(Ink.doorway)
                .place(70, 146, 20, Self.groundY - 146)

            // 門上的小燈
            Circle()
                .fill(Theme.amber.opacity(0.85))
                .place(78.5, 138, 3, 3)
        }
        .scaleEffect(appeared ? 1 : 0.82, anchor: .bottom)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.75, bounce: 0.28).delay(0.05), value: appeared)
    }

    private var clockFace: some View {
        SceneClock()
            .clipShape(Circle())
            .overlay(Circle().stroke(Ink.roof, lineWidth: 2))
    }

    private var mainBlock: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Ink.wall)
                .place(100, 66, 132, Self.groundY - 66)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Ink.roof)
                .place(95, 60, 142, 8)

            ForEach(0..<12, id: \.self) { index in
                let col = index % 4
                let row = index / 4
                window(isLit: isLit(index))
                    .place(110 + CGFloat(col) * 30, 80 + CGFloat(row) * 30, 21, 23)
            }
        }
        .scaleEffect(appeared ? 1 : 0.88, anchor: .bottom)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.7, bounce: 0.24).delay(0.14), value: appeared)
    }

    /// 第 `index` 扇窗是否亮著 —— 依打散過的順序決定。
    private func isLit(_ index: Int) -> Bool {
        guard let rank = Self.lightOrder.firstIndex(of: index) else { return false }
        return rank < litWindows
    }

    private func window(isLit: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isLit ? Ink.windowLit : Ink.windowDark)
                .shadow(color: isLit ? Theme.amber.opacity(0.55) : .clear, radius: 7)

            // 窗框：一豎一橫，讓窗戶不只是個色塊
            Rectangle().fill(Ink.wall.opacity(0.9)).frame(width: 1.4)
            Rectangle().fill(Ink.wall.opacity(0.9)).frame(height: 1.4)
        }
        .animation(.spring(duration: 0.55, bounce: 0.2), value: isLit)
    }

    /// 建築底下的台階，把整棟樓「放」在地上。
    private var plinth: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Ink.roof.opacity(0.55))
            .place(88, Self.groundY - 5, 156, 7)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)
    }

    // MARK: - 旗桿

    private func flag(t: TimeInterval) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Ink.roof)
                .place(215, 18, 2, 46)

            WavingFlag(phase: t * 3.4)
                .fill(Theme.accent)
                .place(217, 21, 30, 17)
                .scaleEffect(x: appeared ? 1 : 0.05, anchor: .leading)
                .opacity(appeared ? 1 : 0)
        }
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.8, bounce: 0.2).delay(0.38), value: appeared)
    }

    // MARK: - 植栽與路燈

    private var tree: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Ink.trunk)
                .place(258, 126, 6, Self.groundY - 126)
            Circle().fill(Ink.leafDeep).place(233, 118, 34, 34)
            Circle().fill(Ink.leafDeep).place(266, 116, 32, 32)
            Circle().fill(Ink.leaf).place(240, 92, 46, 46)
        }
        .scaleEffect(appeared ? 1 : 0.7, anchor: .bottom)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.7, bounce: 0.34).delay(0.26), value: appeared)
    }

    private var bush: some View {
        ZStack(alignment: .topLeading) {
            Ellipse().fill(Ink.leafDeep).place(102, 158, 38, 16)
            Ellipse().fill(Ink.leaf).place(112, 154, 24, 18)
        }
        .scaleEffect(appeared ? 1 : 0.6, anchor: .bottom)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.6, bounce: 0.35).delay(0.32), value: appeared)
    }

    private func lamp(t: TimeInterval) -> some View {
        let pulse = 0.55 + 0.12 * sin(t * 1.6)
        return ZStack(alignment: .topLeading) {
            RadialGradient(colors: [Theme.amber.opacity(pulse), .clear],
                           center: .center, startRadius: 1, endRadius: 34)
                .place(8, 74, 68, 68)

            Rectangle()
                .fill(Ink.roof)
                .place(41, 110, 3, Self.groundY - 110)
            Circle()
                .fill(Theme.amber)
                .place(36, 102, 13, 13)
                .shadow(color: Theme.amber.opacity(0.7), radius: 6)
            // 燈罩
            UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5, style: .continuous)
                .fill(Ink.roof)
                .place(34, 98, 17, 7)
        }
        .scaleEffect(appeared ? 1 : 0.8, anchor: .bottom)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.6, bounce: 0.2).delay(0.2), value: appeared)
    }

    // MARK: - 天空

    private func cloud(t: TimeInterval) -> some View {
        let x = (t * 5).truncatingRemainder(dividingBy: 430) - 70
        return CloudShape()
            .fill(Ink.cloud)
            .place(x, 14, 62, 26)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.8).delay(0.45), value: appeared)
    }

    private func birds(t: TimeInterval) -> some View {
        let drift = (t * 8).truncatingRemainder(dividingBy: 460) - 80
        return ZStack(alignment: .topLeading) {
            bird(flap: sin(t * 5.0)).place(drift, 46, 12, 8)
            bird(flap: sin(t * 5.0 + 0.9)).place(drift + 17, 38, 10, 7)
        }
        .opacity(appeared ? 0.75 : 0)
        .animation(.easeOut(duration: 0.8).delay(0.55), value: appeared)
    }

    private func bird(flap: Double) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 6))
            p.addQuadCurve(to: CGPoint(x: 5, y: 1 + flap), control: CGPoint(x: 2, y: 0))
            p.addQuadCurve(to: CGPoint(x: 10, y: 6), control: CGPoint(x: 8, y: 0))
        }
        .stroke(Ink.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }

    // MARK: - 地面

    private var ground: some View {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 288, y: 0))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
            .foregroundStyle(Ink.ink.opacity(0.16))
            .place(16, Self.groundY + 2, 288, 2)

            // 幾撮草，隨手點的那種
            grassTuft.place(150, Self.groundY - 5, 8, 7)
            grassTuft.place(206, Self.groundY - 4, 7, 6)
            grassTuft.place(62, Self.groundY - 4, 7, 6)
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.5), value: appeared)
    }

    private var grassTuft: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 7)); p.addQuadCurve(to: CGPoint(x: 2, y: 0), control: CGPoint(x: 0, y: 3))
            p.move(to: CGPoint(x: 4, y: 7)); p.addQuadCurve(to: CGPoint(x: 7, y: 1), control: CGPoint(x: 6, y: 4))
        }
        .stroke(Ink.leaf, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
    }
}

// MARK: - 時鐘

/// 塔樓上的時鐘，指的是現在的時間。指針由 `sceneClockDate` 餵進來，
/// 跟著外層 TimelineView 一起更新，不必自己再開一個計時器。
private struct SceneClock: View {
    @Environment(\.sceneClockDate) private var date

    var body: some View {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minute = Double(comps.minute ?? 0)
        let hour = Double((comps.hour ?? 0) % 12) + minute / 60

        ZStack {
            Circle().fill(Ink.clockFace)

            // 12 / 3 / 6 / 9 的刻度
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(Ink.roof.opacity(0.6))
                    .frame(width: 1.4, height: 3)
                    .offset(y: -9.5)
                    .rotationEffect(.degrees(Double(i) * 90))
            }

            hand(length: 6, width: 2, angle: hour / 12 * 360)
            hand(length: 8.5, width: 1.4, angle: minute / 60 * 360)

            Circle().fill(Ink.roof).frame(width: 2.5, height: 2.5)
        }
    }

    private func hand(length: CGFloat, width: CGFloat, angle: Double) -> some View {
        Capsule()
            .fill(Ink.roof)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(angle))
    }
}

private struct SceneClockDateKey: EnvironmentKey {
    static let defaultValue = Date()
}

private extension EnvironmentValues {
    var sceneClockDate: Date {
        get { self[SceneClockDateKey.self] }
        set { self[SceneClockDateKey.self] = newValue }
    }
}

// MARK: - 雲

/// 一朵雲 = 一條路徑。大小不一的幾個弧疊在同一個 subpath 集合裡，用 nonzero
/// 填滿後只剩外輪廓，不會在交疊處疊出第二層顏色（那正是「三個圓圈」的來源）。
private struct CloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        // 平坦的底
        path.addRoundedRect(
            in: CGRect(x: 0, y: h * 0.52, width: w, height: h * 0.48),
            cornerSize: CGSize(width: h * 0.24, height: h * 0.24)
        )
        // 三團大小不同的雲峰
        path.addEllipse(in: CGRect(x: w * 0.02, y: h * 0.34, width: w * 0.42, height: h * 0.52))
        path.addEllipse(in: CGRect(x: w * 0.26, y: h * 0.02, width: w * 0.46, height: h * 0.78))
        path.addEllipse(in: CGRect(x: w * 0.58, y: h * 0.28, width: w * 0.38, height: h * 0.58))
        return path
    }
}

// MARK: - 旗子

/// 被風吹著的旗子：上下兩條邊各自帶一段正弦波，越靠旗尾擺得越大。
private struct WavingFlag: Shape {
    var phase: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        let step: CGFloat = 3

        func wave(_ x: CGFloat) -> CGFloat {
            sin(Double(x) / 9 + phase) * 3.4 * Double(x / w)
        }

        path.move(to: CGPoint(x: 0, y: 0))
        for x in stride(from: CGFloat(0), through: w, by: step) {
            path.addLine(to: CGPoint(x: x, y: wave(x)))
        }
        for x in stride(from: w, through: CGFloat(0), by: -step) {
            path.addLine(to: CGPoint(x: x, y: h + wave(x)))
        }
        path.closeSubpath()
        return path
    }
}

#Preview("白天") {
    CampusScene(litWindows: 5)
        .frame(height: 240)
        .background(Theme.background)
}

#Preview("全亮") {
    CampusScene(litWindows: 12)
        .frame(height: 240)
        .background(Theme.background)
        .preferredColorScheme(.dark)
}
