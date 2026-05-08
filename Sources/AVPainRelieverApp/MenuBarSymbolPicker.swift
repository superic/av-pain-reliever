import SwiftUI

/// Popover content for the menu bar icon picker in Settings → General.
/// Renders `MenuBarIcon.catalog` as a 6-column grid; clicking a tile
/// updates the binding and dismisses the popover.
///
/// Visual sibling of `IconPickerView` (the wizard's per-profile
/// picker) — same tile size, same selection-highlight treatment via
/// the shared `IconTile`, so the two pickers read as one component
/// family. The reason this is a separate view instead of generalising
/// `IconPickerView`: the wizard picker has an "Auto" affordance keyed
/// to a profile slug, which makes no sense for a global menu-bar
/// default. A standalone view keeps both call sites simple.
struct MenuBarSymbolPicker: View {
    /// User's current pick. Non-optional because the menu bar always
    /// has a fallback symbol — `nil` would have no useful meaning.
    @Binding var selection: String

    /// Called after a tap, so the caller can dismiss the popover.
    let onPick: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(40), spacing: 6), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(MenuBarIcon.catalog, id: \.self) { symbol in
                IconTile(symbol: symbol, isSelected: selection == symbol) {
                    selection = symbol
                    onPick()
                }
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}
