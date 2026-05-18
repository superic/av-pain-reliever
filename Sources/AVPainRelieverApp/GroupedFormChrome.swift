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
    /// caller follows.
    ///
    /// **Don't wrap the Form in a container that adds horizontal
    /// padding.** e.g. avoid:
    ///
    ///     VStack {
    ///         Form { ... }.groupedFormChrome()
    ///     }.padding(.horizontal, 20)  // ← wrong
    ///
    /// The point of this modifier is to let the Form fill its
    /// container edge-to-edge so it lines up with how a Settings
    /// tab renders inside SwiftUI's `Settings { ... }` scene.
    /// Outer horizontal padding on the container narrows the
    /// gray cards beyond Settings' visual; this exact bug was
    /// fixed in the wizard layout. If sibling elements (buttons
    /// row, error banner, etc.) need their own margin from the
    /// window edge, pad each one individually with
    /// `.padding(.horizontal, …)` — see `AddProfileView.body`.
    func groupedFormChrome() -> some View {
        self
            .formStyle(.grouped)
            .padding(8)
    }
}
