import SwiftUI
import AppKit

/// SwiftUI view modifier that locks the hosting `NSWindow` to a fixed,
/// dialog-style chrome: title bar + close button only. The yellow
/// minimize button and the green zoom button are removed from
/// `styleMask`, which renders them greyed-out in the title bar — the
/// macOS-native way to indicate "this window doesn't do that," more
/// idiomatic than hiding them entirely.
///
/// Pair with a fixed `.frame(width:height:)` and (at the Window scene
/// level) `.windowResizability(.contentSize)` to fully prevent
/// resizing.
///
/// Why an NSViewRepresentable: SwiftUI doesn't expose enough of the
/// hosting NSWindow to flip individual traffic-light affordances,
/// even on macOS 14+. The transparent helper view sits in the
/// background and grabs `view.window` once it's installed, then
/// configures the chrome.
struct DialogWindowChrome: ViewModifier {
    func body(content: Content) -> some View {
        content.background(WindowChromeAccessor())
    }
}

extension View {
    /// Lock the hosting window to dialog chrome (title + close, no
    /// minimize, no zoom). See `DialogWindowChrome`.
    func dialogWindowChrome() -> some View {
        modifier(DialogWindowChrome())
    }
}

private struct WindowChromeAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // The view isn't in a window yet at make-time — defer until
        // the window has wired itself up.
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            applyDialogChrome(to: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-apply on update in case SwiftUI re-hosted the window.
        // Cheap, idempotent.
        if let window = nsView.window {
            applyDialogChrome(to: window)
        }
    }

    /// Trim the styleMask so only title + close remain. SwiftUI's
    /// `.windowResizability(.contentSize)` already drops `.resizable`
    /// from the mask, but explicitly removing it here makes the
    /// intent local to the helper rather than spread across the
    /// scene graph.
    private func applyDialogChrome(to window: NSWindow) {
        window.styleMask.remove(.miniaturizable)
        window.styleMask.remove(.resizable)
        // Belt-and-suspenders: even with the styleMask flag dropped,
        // some SwiftUI versions leave the buttons enabled. Disable
        // them explicitly so a click is a no-op rather than a beep.
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
    }
}

// MARK: - centeredOnScreen

/// SwiftUI view modifier that recenters the hosting `NSWindow` on the
/// active screen every time the window appears. Without this, macOS
/// remembers each window's last position and reopens it there, which
/// produces the surprising "settings window opened in some random
/// corner of the second monitor" experience for utility windows.
struct CenteredOnScreen: ViewModifier {
    func body(content: Content) -> some View {
        content.background(WindowCenterer())
    }
}

extension View {
    /// Center the hosting window on the active screen on every open.
    /// Idempotent — safe to combine with `dialogWindowChrome()`.
    func centeredOnScreen() -> some View {
        modifier(CenteredOnScreen())
    }
}

private struct WindowCenterer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            view?.window?.center()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op on update. Centering on every state change would
        // fight the user if they manually move the window mid-
        // session. We only center on open.
    }
}
