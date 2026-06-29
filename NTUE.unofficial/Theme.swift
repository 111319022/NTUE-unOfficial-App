import SwiftUI
import UIKit

/// Centralised colours & styling — the "暖調學院" palette: a warm cream canvas,
/// NTUE maroon as the brand accent, and amber for secondary highlights. Colours
/// adapt for dark mode via `Color(light:dark:)`.
enum Theme {
    /// NTUE maroon — deep in light mode, brightened in dark mode so it stays legible.
    static let accent = Color(
        light: Color(red: 0.56, green: 0.17, blue: 0.17),
        dark:  Color(red: 0.93, green: 0.45, blue: 0.48)
    )
    /// Tinted background behind the accent (avatars, hero pills, etc.).
    static let accentSoft = Color(
        light: Color(red: 0.56, green: 0.17, blue: 0.17).opacity(0.12),
        dark:  Color(red: 0.93, green: 0.45, blue: 0.48).opacity(0.22)
    )

    /// Solid maroon for large fills behind WHITE text (hero card, filled buttons).
    /// Stays deep in both modes — unlike `accent`, which brightens for use as a
    /// foreground colour on dark surfaces.
    static let accentFill = Color(
        light: Color(red: 0.56, green: 0.17, blue: 0.17),
        dark:  Color(red: 0.66, green: 0.20, blue: 0.23)
    )

    /// Category icon colours for the 其他服務 list (mode-stable, white glyph on top).
    static let iconMaroon = Color(red: 0.60, green: 0.17, blue: 0.18)
    static let iconAmber  = Color(red: 0.82, green: 0.53, blue: 0.13)
    static let iconBlue   = Color(red: 0.20, green: 0.47, blue: 0.72)

    /// Secondary accent — amber, used for "due soon" / highlights.
    static let amber = Color(
        light: Color(red: 0.72, green: 0.46, blue: 0.10),
        dark:  Color(red: 0.91, green: 0.66, blue: 0.27)
    )

    /// Warm page canvas (replaces systemGroupedBackground).
    static let background = Color(
        light: Color(red: 0.965, green: 0.945, blue: 0.914),
        dark:  Color(red: 0.102, green: 0.090, blue: 0.078)
    )
    /// Card / raised-surface colour (replaces secondarySystemGroupedBackground).
    static let cardBackground = Color(
        light: Color(red: 1.0, green: 0.992, blue: 0.976),
        dark:  Color(red: 0.149, green: 0.133, blue: 0.125)
    )

    static func scoreColor(_ score: Double?) -> Color {
        guard let score else { return .secondary }
        switch score {
        case 90...: return Color(light: Color(red: 0.13, green: 0.55, blue: 0.30),
                                 dark:  Color(red: 0.36, green: 0.78, blue: 0.50))   // green
        case 80..<90: return Color(light: Color(red: 0.18, green: 0.45, blue: 0.70),
                                   dark:  Color(red: 0.42, green: 0.67, blue: 0.95)) // blue
        case 60..<80: return .primary
        default: return Color(light: Color(red: 0.80, green: 0.22, blue: 0.22),
                              dark:  Color(red: 0.98, green: 0.45, blue: 0.45))      // red
        }
    }

    /// A stable pastel colour for a course, used in the timetable grid.
    static func courseColor(for key: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.95, green: 0.42, blue: 0.42),
            Color(red: 0.36, green: 0.62, blue: 0.86),
            Color(red: 0.40, green: 0.73, blue: 0.52),
            Color(red: 0.96, green: 0.66, blue: 0.34),
            Color(red: 0.64, green: 0.50, blue: 0.84),
            Color(red: 0.36, green: 0.72, blue: 0.74),
            Color(red: 0.88, green: 0.52, blue: 0.66),
        ]
        let hash = abs(key.hashValue)
        return palette[hash % palette.count]
    }
}

/// A reusable card container.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.accent
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

extension Color {
    /// A colour that resolves differently in light vs dark mode.
    init(light: Color, dark: Color) {
        self = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
