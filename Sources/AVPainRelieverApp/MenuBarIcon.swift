import Foundation

/// Curated catalog of SF Symbols offered as the menu bar's default
/// icon. The user picks one in Settings → General → Behavior; the
/// menu bar shows their pick whenever no per-profile icon is active.
///
/// Kept short and product-relevant: every entry should read at the
/// 17pt menu-bar size and feel at home on a status menu next to the
/// system clock. Big abstract scenery (mountains, bookshelves) lives
/// in `ProfileIcon.catalog` for per-location picks; this one is the
/// "what shape represents the app" question.
enum MenuBarIcon {
    /// Default symbol when the user has never touched the picker.
    /// Matches the SF Symbol used for the app icon and the in-app
    /// "USB fingerprint" section header — Dock, menu bar, and the
    /// wizard share one vocabulary.
    static let defaultSymbol: String = Theme.Symbol.usbSection

    /// Display order: brand glyphs first, then audio signal /
    /// hardware, then video, then control surfaces, then connectivity.
    /// Curated by hand — every entry has been eyeballed at 17pt menu
    /// bar size to confirm it reads cleanly there.
    static let catalog: [String] = [
        // Brand
        "pills.fill",
        "capsule.fill",
        "cross.case.fill",
        // Audio — signal
        "waveform",
        "dot.radiowaves.left.and.right",
        "bolt.fill",
        // Audio — hardware
        "mic.fill",
        "speaker.wave.2.fill",
        "headphones",
        "earbuds",
        // Video
        "camera.fill",
        "video.fill",
        // Control / switching
        "dial.high",
        "slider.horizontal.3",
        "arrow.left.arrow.right",
        "wand.and.stars",
        // Connectivity
        "externaldrive.connected.to.line.below",
        // The eighteenth slot — fills the orphan cell in the 6×3
        // grid and ties back to the About / Welcome confetti.
        "party.popper.fill",
    ]
}
