import SwiftUI

/// 36×36 tappable SF Symbol tile used by both `IconPickerView` (the
/// wizard's per-profile icon picker) and `MenuBarSymbolPicker` (the
/// global menu-bar icon picker). Selection treatment: tinted accent
/// fill plus a 1-point accent stroke so the chosen tile stands out
/// against the unselected ones. Caller owns the symbol catalog and
/// the selection state — this view only renders one cell.
struct IconTile: View {
    let symbol: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            onTap()
        } label: {
            Image(systemName: symbol)
                .font(.body)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected
                              ? Color.accentColor.opacity(0.18)
                              : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? Color.accentColor
                                : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .help(symbol)
    }
}
