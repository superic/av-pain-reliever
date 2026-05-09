import SwiftUI

extension Binding {
    /// Bridges a `Binding<T?>` to a `Binding<Bool>` for SwiftUI APIs
    /// that take an `isPresented:` flag (`.alert`, `.sheet`, etc.).
    /// Reads true while the source is non-nil; writing false clears
    /// the source. Writing true is a no-op because the source's
    /// payload is what determines the presented state, not the bool.
    static func isPresent<Wrapped>(_ source: Binding<Wrapped?>) -> Binding<Bool> where Value == Bool {
        Binding<Bool>(
            get: { source.wrappedValue != nil },
            set: { presented in
                if !presented { source.wrappedValue = nil }
            }
        )
    }
}
