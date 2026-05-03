import SwiftUI

/// Bordered icon-only button with a fixed icon-frame so multiple
/// IconButtons rendered side-by-side end up at identical heights
/// regardless of which SF Symbol each one carries.
///
/// Why this exists as a standalone view: SF Symbols of different
/// designs (e.g. `pencil` vs `trash`) have intrinsically different
/// glyph bounds at the same `.font(...)` size. A `.bordered` button
/// auto-sizes to its content + chrome padding, so a row of plain
/// `Button { Label(...) }` instances ends up with mismatched
/// dimensions when the icons differ in metric. Pinning the inner
/// `Image` to a fixed 18×20 frame — larger than either glyph's
/// intrinsic content — neutralises the difference: each icon
/// renders centred inside the same-size box, so each button's
/// auto-sized chrome lands at the same dimensions too.
///
/// Accessibility: VoiceOver reads `accessibilityLabel`. A `.help(...)`
/// tooltip surfaces the same string to sighted users hovering over
/// the icon.
struct IconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let role: ButtonRole?
    let action: () -> Void

    init(
        systemImage: String,
        accessibilityLabel: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Label {
                Text(accessibilityLabel)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .regular))
                    // 18×20 is empirically large enough to contain
                    // every SF Symbol we currently use in this
                    // role at 14pt. If a future button uses a
                    // taller glyph and ends up clipped, this is
                    // the dial to widen.
                    .frame(width: 18, height: 20)
            }
        }
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
        .help(accessibilityLabel)
    }
}
