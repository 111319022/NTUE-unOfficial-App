import SwiftUI

/// 插圖的共用底層：一張固定比例的設計稿 + 一組配色。
///
/// 所有手繪插圖都畫在自己的設計稿座標系上（左上角為原點），再由 `DesignCanvas`
/// 等比縮放去貼齊外框的寬度、對齊底部。這樣同一張圖放在登入頁、初始化頁或
/// Onboarding 的任何高度裡，比例和地平線的位置都一致。
struct DesignCanvas<Content: View>: View {
    let size: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / size.width, geo.size.height / size.height)

            ZStack(alignment: .topLeading) {
                // 撐出整張設計稿的大小。少了這塊，ZStack 只會長到最大那個子元件
                // 那麼大，外面再套 .frame 會把內容置中 —— 每個元件的絕對座標
                // 就整組偏掉了。
                Color.clear.frame(width: size.width, height: size.height)
                content
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale, anchor: .bottom)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

extension View {
    /// 把元素放到設計稿上的絕對位置（左上角座標）。
    func place(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> some View {
        frame(width: w, height: h).offset(x: x, y: y)
    }
}

/// 插圖用色。品牌色沿用 `Theme`，其餘（磚牆陰影、木頭、樹、雲）是為了這組圖
/// 挑的暖色系配色，深色模式另給一組值，免得夜裡整張圖糊成一團。
enum Ink {
    static let wall = Theme.accentFill
    static let wallShade = Color(
        light: Color(red: 0.46, green: 0.14, blue: 0.14),
        dark:  Color(red: 0.54, green: 0.17, blue: 0.19)
    )
    static let roof = Color(
        light: Color(red: 0.33, green: 0.10, blue: 0.11),
        dark:  Color(red: 0.40, green: 0.13, blue: 0.15)
    )
    static let doorway = Color(
        light: Color(red: 0.28, green: 0.09, blue: 0.10),
        dark:  Color(red: 0.20, green: 0.08, blue: 0.10)
    )
    static let windowDark = Color(
        light: Color(red: 0.31, green: 0.14, blue: 0.15),
        dark:  Color(red: 0.19, green: 0.11, blue: 0.12)
    )
    static let windowLit = Color(
        light: Color(red: 1.00, green: 0.87, blue: 0.62),
        dark:  Color(red: 1.00, green: 0.83, blue: 0.55)
    )
    static let clockFace = Color(
        light: Color(red: 0.99, green: 0.97, blue: 0.92),
        dark:  Color(red: 0.93, green: 0.89, blue: 0.82)
    )
    static let leaf = Color(
        light: Color(red: 0.42, green: 0.55, blue: 0.36),
        dark:  Color(red: 0.45, green: 0.58, blue: 0.41)
    )
    static let leafDeep = Color(
        light: Color(red: 0.31, green: 0.43, blue: 0.29),
        dark:  Color(red: 0.32, green: 0.44, blue: 0.31)
    )
    static let trunk = Color(
        light: Color(red: 0.45, green: 0.33, blue: 0.24),
        dark:  Color(red: 0.38, green: 0.29, blue: 0.22)
    )
    /// 桌面、木頭 —— 比樹幹淺一階。
    static let wood = Color(
        light: Color(red: 0.72, green: 0.56, blue: 0.40),
        dark:  Color(red: 0.47, green: 0.36, blue: 0.27)
    )
    static let cloud = Color(
        light: Color.white.opacity(0.75),
        dark:  Color.white.opacity(0.13)
    )
    /// 紙張 / 卡片 —— 插圖裡代表 UI 介面的那些面。
    static let paper = Theme.cardBackground
    /// 書口的紙。深色模式下也要維持是「紙」，不能跟著背景變黑。
    static let pages = Color(
        light: Color(red: 0.99, green: 0.97, blue: 0.93),
        dark:  Color(red: 0.87, green: 0.84, blue: 0.78)
    )
    /// 陶瓷（杯子）。
    static let ceramic = Color(
        light: Color(red: 0.97, green: 0.95, blue: 0.92),
        dark:  Color(red: 0.79, green: 0.76, blue: 0.73)
    )
    static let hair = Color.primary.opacity(0.12)
    static let ink = Color.primary
}
