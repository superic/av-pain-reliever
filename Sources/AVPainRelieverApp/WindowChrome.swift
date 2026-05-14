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

/// SwiftUI view modifier that centers the hosting `NSWindow` on the
/// screen with the mouse cursor when the window first appears. Without
/// this, macOS remembers each window's last position and reopens it
/// there, producing the surprising "settings window opened in some
/// random corner of the second monitor" experience for utility windows.
///
/// Centers **synchronously** in `viewDidMoveToWindow`, before AppKit
/// orders the window front. An earlier implementation used a
/// `DispatchQueue.main.async` hop, which deferred the centering past
/// the show, producing a visible flash where the window appeared at
/// its saved position and then snapped to center one runloop later.
struct CenteredOnScreen: ViewModifier {
    func body(content: Content) -> some View {
        content.background(WindowCenterer())
    }
}

extension View {
    /// Center the hosting window on the active screen on first open.
    /// Idempotent across re-hosting; the window is only centered once
    /// per view instance so a user-moved window isn't yanked back.
    func centeredOnScreen() -> some View {
        modifier(CenteredOnScreen())
    }
}

private struct WindowCenterer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowCenteringView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op on update. Centering on every state change would
        // fight the user if they manually moved the window mid-
        // session.
    }
}

/// Centers its hosting window the first time the view is attached.
/// `viewDidMoveToWindow` runs after the window exists but before it
/// is ordered front, so the center call lands before the user sees
/// anything. The `hasCentered` latch guards against SwiftUI re-hosting
/// the view later (theme change, scene restoration), which would
/// otherwise re-center and clobber a user-moved window.
private final class WindowCenteringView: NSView {
    private var hasCentered = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !hasCentered, let window = window else { return }
        hasCentered = true
        centerOnCursorScreen(window)
    }

    /// Center on the screen currently containing the mouse cursor.
    /// For a menu-bar app the user may click the menu bar on monitor
    /// A while the saved frame is on monitor B; the cursor's screen
    /// is the screen they're looking at. Falls back to `NSWindow.center()`
    /// (main screen) when no screen contains the cursor — typically
    /// only happens during screen-reconfiguration races.
    private func centerOnCursorScreen(_ window: NSWindow) {
        let cursor = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
            ?? NSScreen.main
        else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = visible.origin.x + (visible.width - frame.width) / 2
        // Match AppKit's `NSWindow.center()` heuristic: place the
        // window above geometric center (about a third from the top
        // of the screen), which reads as "primary attention" for a
        // utility window rather than "bottom-of-the-stack."
        frame.origin.y = visible.origin.y + (visible.height - frame.height) * 2 / 3
        window.setFrame(frame, display: true)
    }
}
