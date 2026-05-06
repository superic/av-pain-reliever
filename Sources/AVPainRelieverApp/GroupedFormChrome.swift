import SwiftUI

extension View {
    /// Shared chrome for every grouped-`Form` surface in the app
    /// (Settings tabs, the Add/Edit Profile wizard, anywhere we
    /// render a `Form { ... }.formStyle(.grouped)`). Bundles the
    /// formStyle + the 8pt outer padding that gives the gray
    /// rounded section cards consistent breathing room against
    /// the window edges.
    ///
    /// One place to change the convention. If we ever bump the
    /// padding, swap to a different formStyle, or add other shared
    /// chrome (background, frame, etc.), edit it here and every
    /// caller follows. The Profiles Settings tab is intentionally
    /// bespoke (no Form, different layout) and doesn't use this.
    func groupedFormChrome() -> some View {
        self
            .formStyle(.grouped)
            .padding(8)
    }
}
