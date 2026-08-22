import SwiftUI

// MARK: - 書桌一角

/// Onboarding 第一頁：檯燈底下的一疊課本、一支筆、一杯還在冒煙的飲料。
/// 和校園小景同一套畫法（扁平色塊 + 暖色系），只是把鏡頭拉到桌上。
struct DeskHero: View {
    var appeared: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let canvas = CGSize(width: 320, height: 186)
    private static let deskY: CGFloat = 152

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.amber.opacity(0.14), Theme.accent.opacity(0.04)],
                           startPoint: .top, endPoint: .bottom)

            DesignCanvas(size: Self.canvas) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                    let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

                    ZStack(alignment: .topLeading) {
                        lightCone
                        lamp
                        steam(t: t)
                        mug
                        books
                        desk
                    }
                }
            }
        }
        .clipped()
    }

    // MARK: 桌面

    private var desk: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Ink.wood)
                .place(0, Self.deskY, 320, 11)
            Rectangle()
                .fill(Ink.trunk.opacity(0.45))
                .place(0, Self.deskY + 11, 320, 6)
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: appeared)
    }

    // MARK: 檯燈

    private var lamp: some View {
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(Ink.roof)
                .place(10, 140, 52, 12)
            Path { p in
                p.move(to: CGPoint(x: 0, y: 86))
                p.addQuadCurve(to: CGPoint(x: 17, y: 0), control: CGPoint(x: -5, y: 32))
            }
            .stroke(Ink.roof, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .place(35, 62, 20, 86)

            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 54, y: 0))
                p.addLine(to: CGPoint(x: 43, y: 26))
                p.addLine(to: CGPoint(x: 11, y: 26))
                p.closeSubpath()
            }
            .fill(Theme.accentFill)
            .place(26, 40, 54, 26)

            Circle()
                .fill(Theme.amber)
                .place(45, 58, 16, 16)
                .shadow(color: Theme.amber.opacity(0.8), radius: 8)
        }
        .scaleEffect(appeared ? 1 : 0.85, anchor: .bottom)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.6, bounce: 0.25).delay(0.04), value: appeared)
    }

    /// 檯燈灑下來的光。
    private var lightCone: some View {
        Path { p in
            p.move(to: CGPoint(x: 30, y: 0))
            p.addLine(to: CGPoint(x: 78, y: 0))
            p.addLine(to: CGPoint(x: 126, y: 86))
            p.addLine(to: CGPoint(x: 0, y: 86))
            p.closeSubpath()
        }
        .fill(
            LinearGradient(colors: [Theme.amber.opacity(0.30), Theme.amber.opacity(0.02)],
                           startPoint: .top, endPoint: .bottom)
        )
        .place(0, 66, 126, 86)
        .blur(radius: 6)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.9).delay(0.3), value: appeared)
    }

    // MARK: 課本

    private var books: some View {
        ZStack(alignment: .topLeading) {
            book(x: 76, y: 132, w: 150, h: 20, tilt: -1.2, color: Ink.wall, delay: 0.10)
            book(x: 88, y: 112, w: 130, h: 20, tilt: 1.1, color: Theme.amber, delay: 0.18)
            book(x: 80, y: 92, w: 142, h: 20, tilt: -0.6, color: Ink.leaf, delay: 0.26)
        }
    }

    private func book(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                      tilt: Double, color: Color, delay: Double) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .place(0, 0, w, h)
            // 書口（紙頁那一側）
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Ink.pages)
                .place(w - 11, 4, 7, h - 8)
            // 書背上的一條裝飾線
            Capsule()
                .fill(Color.white.opacity(0.30))
                .place(10, h / 2 - 1.5, 30, 3)
        }
        .frame(width: w, height: h)
        .rotationEffect(.degrees(tilt))
        .offset(x: x, y: appeared ? y : y + 20)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.6, bounce: 0.3).delay(delay), value: appeared)
    }

    // MARK: 杯子

    private var mug: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .strokeBorder(Ink.ceramic, lineWidth: 7)
                .place(278, 108, 32, 32)
            UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 18,
                                   bottomTrailingRadius: 18, topTrailingRadius: 5,
                                   style: .continuous)
                .fill(Ink.ceramic)
                .place(236, 96, 54, 56)
            Capsule()
                .fill(Theme.accent.opacity(0.85))
                .place(242, 114, 42, 7)
        }
        .scaleEffect(appeared ? 1 : 0.6, anchor: .bottom)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.55, bounce: 0.35).delay(0.32), value: appeared)
    }

    /// 兩縷往上飄的熱氣，飄到頂就淡出重來。
    private func steam(t: TimeInterval) -> some View {
        ZStack(alignment: .topLeading) {
            wisp(phase: (t * 0.34).truncatingRemainder(dividingBy: 1), x: 246)
            wisp(phase: ((t * 0.34) + 0.5).truncatingRemainder(dividingBy: 1), x: 268)
        }
        .opacity(appeared && !reduceMotion ? 1 : 0)
        .animation(.easeOut(duration: 0.6).delay(0.5), value: appeared)
    }

    private func wisp(phase: Double, x: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 5, y: 34))
            p.addQuadCurve(to: CGPoint(x: 0, y: 17), control: CGPoint(x: 12, y: 26))
            p.addQuadCurve(to: CGPoint(x: 6, y: 0), control: CGPoint(x: -6, y: 8))
        }
        .stroke(Ink.ink.opacity(0.20), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .place(x, 66 - CGFloat(phase) * 26, 13, 34)
        .opacity(sin(phase * .pi))
    }

}

// MARK: - 課表

/// Onboarding 第二頁：一張正在長出課程的週課表。格子一格一格跳進來，
/// 「現在這堂」會一直輕輕呼吸。
struct TimetableHero: View {
    var appeared: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let canvas = CGSize(width: 320, height: 186)

    /// (第幾欄, 第幾列, 佔幾列, 顏色代號)
    private static let blocks: [(col: Int, row: Int, span: Int, key: String)] = [
        (0, 0, 1, "國音及說話"),
        (2, 0, 2, "教育心理學"),
        (1, 1, 1, "兒童文學"),
        (4, 1, 1, "體育"),
        (0, 2, 1, "數學教材教法"),
        (3, 3, 1, "英文"),
    ]
    /// 呼吸的那一格 = 現在正在上的課。
    private static let currentBlock = 1

    private static let originX: CGFloat = 42
    private static let originY: CGFloat = 62
    private static let colWidth: CGFloat = 40
    private static let colStep: CGFloat = 46
    private static let rowHeight: CGFloat = 22
    private static let rowStep: CGFloat = 26

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent.opacity(0.12), Theme.accent.opacity(0.03)],
                           startPoint: .top, endPoint: .bottom)

            DesignCanvas(size: Self.canvas) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                    let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

                    ZStack(alignment: .topLeading) {
                        card
                        emptyCells
                        courseBlocks(t: t)
                    }
                }
            }
        }
        .clipped()
    }

    private var card: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Ink.paper)
                .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Ink.hair, lineWidth: 1)
                )
                .place(26, 10, 268, 164)

            // 標題列
            Capsule().fill(Ink.hair).place(42, 26, 74, 9)
            Capsule().fill(Theme.accentSoft).place(244, 24, 34, 13)

            // 星期
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Ink.hair)
                    .place(Self.originX + CGFloat(i) * Self.colStep, 46, 22, 6)
            }
        }
        .scaleEffect(appeared ? 1 : 0.94, anchor: .center)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.6, bounce: 0.2), value: appeared)
    }

    private var emptyCells: some View {
        ForEach(0..<20, id: \.self) { index in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .place(Self.originX + CGFloat(index % 5) * Self.colStep,
                       Self.originY + CGFloat(index / 5) * Self.rowStep,
                       Self.colWidth, Self.rowHeight)
        }
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)
    }

    private func courseBlocks(t: TimeInterval) -> some View {
        ForEach(Array(Self.blocks.enumerated()), id: \.offset) { index, block in
            let isCurrent = index == Self.currentBlock
            let breathe = isCurrent && !reduceMotion ? 1 + 0.025 * sin(t * 1.9) : 1
            let height = Self.rowHeight + CGFloat(block.span - 1) * Self.rowStep

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Theme.courseColor(for: block.key).opacity(0.85))
                .overlay(alignment: .topTrailing) {
                    if isCurrent {
                        Circle()
                            .fill(.white.opacity(0.9))
                            .frame(width: 6, height: 6)
                            .padding(4)
                    }
                }
                .place(Self.originX + CGFloat(block.col) * Self.colStep,
                       Self.originY + CGFloat(block.row) * Self.rowStep,
                       Self.colWidth, height)
                .scaleEffect(appeared ? breathe : 0.3)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(duration: 0.5, bounce: 0.4).delay(0.22 + 0.07 * Double(index)),
                           value: appeared)
        }
    }
}

// MARK: - 資料從哪裡來

/// Onboarding 第三頁：資料從 iNTUE 和 Moodle 直接流到手機上，
/// 中間沒有別人。虛線上的小點會一直往手機跑。
struct DataFlowHero: View {
    var appeared: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let canvas = CGSize(width: 320, height: 186)

    private static let routeA = Route(from: CGPoint(x: 120, y: 62),
                                      control: CGPoint(x: 172, y: 44),
                                      to: CGPoint(x: 210, y: 74))
    private static let routeB = Route(from: CGPoint(x: 120, y: 124),
                                      control: CGPoint(x: 172, y: 140),
                                      to: CGPoint(x: 210, y: 104))

    struct Route {
        let from: CGPoint
        let control: CGPoint
        let to: CGPoint

        /// 二次貝茲曲線上的一點。
        func point(at p: Double) -> CGPoint {
            let q = 1 - p
            return CGPoint(
                x: q * q * from.x + 2 * q * p * control.x + p * p * to.x,
                y: q * q * from.y + 2 * q * p * control.y + p * p * to.y
            )
        }

        var path: Path {
            var path = Path()
            path.move(to: from)
            path.addQuadCurve(to: to, control: control)
            return path
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent.opacity(0.10), Theme.amber.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            DesignCanvas(size: Self.canvas) {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
                    let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

                    ZStack(alignment: .topLeading) {
                        wires
                        travellers(t: t)
                        source(label: "iNTUE", y: 40, delay: 0.08)
                        source(label: "Moodle", y: 104, delay: 0.16)
                        phone
                    }
                }
            }
        }
        .clipped()
    }

    private var wires: some View {
        ZStack(alignment: .topLeading) {
            Self.routeA.path
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                .foregroundStyle(Theme.accent.opacity(0.35))
            Self.routeB.path
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 5]))
                .foregroundStyle(Theme.accent.opacity(0.35))
        }
        .place(0, 0, Self.canvas.width, Self.canvas.height)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.3), value: appeared)
    }

    private func travellers(t: TimeInterval) -> some View {
        ZStack(alignment: .topLeading) {
            traveller(on: Self.routeA, progress: (t * 0.38).truncatingRemainder(dividingBy: 1))
            traveller(on: Self.routeB, progress: ((t * 0.38) + 0.45).truncatingRemainder(dividingBy: 1))
        }
        .opacity(appeared && !reduceMotion ? 1 : 0)
    }

    private func traveller(on route: Route, progress: Double) -> some View {
        let point = route.point(at: progress)
        return Circle()
            .fill(Theme.accent)
            .place(point.x - 3.5, point.y - 3.5, 7, 7)
            .opacity(sin(progress * .pi))
    }

    private func source(label: String, y: CGFloat, delay: Double) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Ink.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Ink.hair, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                .place(24, y, 96, 44)

            Circle().fill(Theme.accent).place(36, y + 12, 5, 5)

            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .place(46, y + 6, 62, 18)

            Capsule().fill(Ink.hair).place(36, y + 28, 46, 5)
        }
        .scaleEffect(appeared ? 1 : 0.88, anchor: .leading)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.55, bounce: 0.25).delay(delay), value: appeared)
    }

    private var phone: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Ink.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(Ink.hair, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .place(212, 20, 80, 146)

            UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous)
                .fill(Ink.wall)
                .place(219, 27, 66, 30)

            Capsule().fill(Color.white.opacity(0.45)).place(227, 38, 34, 5)

            Capsule().fill(Ink.hair).place(227, 68, 50, 6)
            Capsule().fill(Ink.hair).place(227, 82, 38, 6)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Theme.amber.opacity(0.75))
                .place(227, 98, 50, 22)
            Capsule().fill(Ink.hair).place(227, 130, 44, 6)
        }
        .scaleEffect(appeared ? 1 : 0.9, anchor: .bottom)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.6, bounce: 0.25).delay(0.2), value: appeared)
    }
}

#Preview("書桌") {
    DeskHero().frame(height: 250).background(Theme.background)
}

#Preview("課表") {
    TimetableHero().frame(height: 250).background(Theme.background)
}

#Preview("資料來源") {
    DataFlowHero().frame(height: 250).background(Theme.background)
}
