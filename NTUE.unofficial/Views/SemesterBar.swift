import SwiftUI

/// One entry in a `SemesterBar` (a semester, or a special item like 歷年總表).
struct SemesterOption: Identifiable, Hashable {
    let id: String
    let label: String
}

/// A persistent top bar for switching semester: `◀ 114 下學期 ▶`. Tap an arrow
/// to move to the previous/next entry, or tap the middle to pick from a menu.
/// `options` must be ordered oldest → newest (special items, e.g. 歷年, go first).
struct SemesterBar: View {
    let options: [SemesterOption]
    @Binding var selectedID: String

    private var index: Int? { options.firstIndex { $0.id == selectedID } }
    private var currentLabel: String { options.first { $0.id == selectedID }?.label ?? "—" }

    var body: some View {
        HStack(spacing: 8) {
            arrow("chevron.left", enabled: (index ?? 0) > 0) { step(-1) }

            Menu {
                ForEach(options.reversed()) { opt in   // newest first in the menu
                    Button {
                        selectedID = opt.id
                    } label: {
                        if opt.id == selectedID {
                            Label(opt.label, systemImage: "checkmark")
                        } else {
                            Text(opt.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(currentLabel).font(.subheadline.bold())
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
            }

            arrow("chevron.right", enabled: (index ?? options.count - 1) < options.count - 1) { step(1) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.cardBackground)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func step(_ delta: Int) {
        guard let i = index else {
            if let first = options.first { selectedID = first.id }
            return
        }
        let n = i + delta
        if options.indices.contains(n) { selectedID = options[n].id }
    }

    private func arrow(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.headline)
                .frame(width: 40, height: 32)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.25)
        .tint(Theme.accent)
    }
}
