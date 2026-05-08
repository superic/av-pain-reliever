import SwiftUI

/// Popover content for the wizard's icon override picker. Renders the
/// curated `ProfileIcon.catalog` as a lazy 6-column grid, plus an
/// "Auto" affordance at the top that clears the override and lets the
/// slug-driven auto-mapper pick.
///
/// Selection updates `binding` and dismisses the popover via the
/// caller-supplied `onPick` closure (SwiftUI's auto-dismiss on
/// background tap is preserved either way; `onPick` is for the
/// explicit selection-then-close flow).
struct IconPickerView: View {
    /// User's choice. `nil` means "auto" — the auto-mapper picks
    /// based on the slug. A non-nil value is one of the SF Symbol
    /// names from `ProfileIcon.catalog`.
    @Binding var selection: String?

    /// The slug currently being edited — used to render the "Auto"
    /// preview so the user can see what auto-mapping would pick. Lets
    /// users compare auto vs override at a glance.
    let slug: String

    /// Called after a selection. The wizard uses this to dismiss the
    /// popover so a tap doesn't require a second click somewhere
    /// else to close it.
    let onPick: () -> Void

    private let columns = Array(repeating: GridItem(.fixed(40), spacing: 6), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // "Auto" row — shows the slug-driven preview so the user
            // can see what auto-mapping picks for this profile name
            // and decide whether to override at all. Selected when
            // `selection` is nil.
            Button {
                selection = nil
                onPick()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: ProfileIcon.symbol(for: slug))
                        .font(.body)
                        .frame(width: 24, height: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Auto")
                            .font(.callout.weight(.medium))
                        Text("Picked from the profile name")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selection == nil {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            // Curated catalog grid. Each cell is an `IconTile`; the
            // selected one (matching `selection`) renders with a
            // tinted background so it stands out against the others.
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(ProfileIcon.catalog, id: \.self) { symbol in
                    IconTile(symbol: symbol, isSelected: selection == symbol) {
                        selection = symbol
                        onPick()
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 300)
    }
}
