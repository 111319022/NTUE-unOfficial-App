import SwiftUI

/// Centralised colours & styling. NTUE's brand is a deep maroon/red.
enum Theme {
    static let accent = Color(red: 0.62, green: 0.16, blue: 0.18)      // NTUE maroon
    static let accentSoft = Color(red: 0.62, green: 0.16, blue: 0.18).opacity(0.12)

    static func scoreColor(_ score: Double?) -> Color {
        guard let score else { return .secondary }
        switch score {
        case 90...: return Color(red: 0.13, green: 0.55, blue: 0.30)   // green
        case 80..<90: return Color(red: 0.18, green: 0.45, blue: 0.70) // blue
        case 60..<80: return .primary
        default: return Color(red: 0.80, green: 0.22, blue: 0.22)      // red
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
            .background(Color(.secondarySystemGroupedBackground))
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
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
